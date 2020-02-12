#!/bin/bash

#########################################################################
# Kernel Build Module for ROS Tool
#########################################################################
#
# This module handles the Linux kernel compilation process for embedded
# targets. It provides functionality for selecting the proper cross-compiler,
# configuring the kernel, building it, and generating a bootable image.
#
# The build process follows these steps:
# 1. Select and set up the cross-compiler toolchain
# 2. Clone or validate the kernel repository
# 3. Set up the initial RAM disk (initrd)
# 4. Apply kernel configuration
# 5. Build the kernel and modules
# 6. Create the bootable image
#
# Each step includes validation and error handling to ensure the build
# proceeds correctly or fails with meaningful error messages.
#
#########################################################################

# Load shared functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"
source "$PROJECT_ROOT/scripts/utils.sh"

#-----------------------------------------------------------------------
# Main Kernel Compilation Function
#-----------------------------------------------------------------------

# compile_kernel()
# 
# Main entry point for kernel compilation.
# Coordinates the entire process of building a kernel for the target platform.
#
# Returns:
#   0 on success, non-zero on failure
#
# Dependencies:
#   - git: for kernel source management
#   - make: for building the kernel
#   - zenity: for GUI interactions (if available)
#
compile_kernel() {
    log_message "INFO" "Starting kernel compilation"
    
    # Check for required tools
    check_command git "git" "fatal" || return 1
    check_command make "build-essential" "fatal" || return 1
    
    # Setup GUI configuration tool
    CONFIG_GUI=$(setup_gui_config)
    
    # Select cross compiler via user interface if available
    local ans=$(zenity --list --text "Choose a cross compiler" --radiolist --column "Pick" --column "Compiler" TRUE "arm-eabi-4.6" FALSE "default" FALSE "gcc-4.8" FALSE "gcc-4.9") || handle_error "Failed to select compiler with zenity" "warning"
    
    if [ -z "$ans" ]; then
        log_message "WARN" "No compiler selected, defaulting to arm-eabi-4.6"
        ans="arm-eabi-4.6"
    fi
    
    log_message "INFO" "Selected compiler: $ans"
    
    # Configure compiler path based on selection
    setup_compiler "$ans"
    
    # Create sys directory if it doesn't exist
    ensure_directory "$PROJECT_ROOT/sys"
    
    cd "$PROJECT_ROOT/sys" || handle_error "Failed to change to sys directory" "fatal"
    
    # Clone kernel repository if not present
    if [ ! -d "$KERNEL_DIR" ]; then
        log_message "INFO" "Cloning kernel repository"
        git clone -b "$KERNEL_BRANCH" "$KERNEL_REPO" || handle_error "Failed to clone kernel repository" "fatal"
        
        # Check if the cloned directory exists but with a different name
        if [ ! -d "linux-rockchip" ]; then
            handle_error "Kernel repository cloned but directory not found" "fatal"
        fi
        
        # Rename directory to match expected name
        mv linux-rockchip "$KERNEL_DIR" || handle_error "Failed to rename kernel directory" "fatal"
    else
        log_message "INFO" "Kernel repository already exists"
        
        # Verify the kernel directory is valid
        if [ ! -f "$KERNEL_DIR/Makefile" ]; then
            handle_error "Kernel directory exists but does not appear to be a valid kernel source tree" "fatal"
        fi
    fi
    
    # Setup initrd
    setup_initrd
    
    cd "$PROJECT_ROOT" || handle_error "Failed to change to project root directory" "fatal"
    
    # Create or restore kernel configuration
    setup_kernel_config
    
    # Build the kernel
    build_kernel "$CONFIG_GUI"
    
    # Create boot image
    create_boot_image
    
    log_message "INFO" "Kernel compilation completed"
}

#-----------------------------------------------------------------------
# Compiler Setup Function
#-----------------------------------------------------------------------

# setup_compiler(compiler_name)
#
# Sets up the cross-compilation toolchain based on user selection.
# This function downloads and extracts the selected compiler if needed,
# then sets the COMPILER_PATH variable for use in kernel build commands.
#
# Parameters:
#   $1 - compiler_name: The name of the compiler to use (arm-eabi-4.6, 
#        default, gcc-4.8, gcc-4.9)
#
# Returns:
#   None (sets global COMPILER_PATH variable)
#
# Environment modified:
#   COMPILER_PATH - Set to the path of the selected compiler
#
setup_compiler() {
    local compiler="$1"
    
    if [ "$compiler" == "default" ]; then
        # Check if the default compiler is available
        if ! check_command arm-linux-gnueabihf-gcc "gcc-arm-linux-gnueabihf" "warning"; then
            log_message "WARN" "Default ARM compiler not found. Falling back to arm-eabi-4.6."
            compiler="arm-eabi-4.6"
        else
            COMPILER_PATH=arm-linux-gnueabihf-
        fi
    elif [ "$compiler" == "gcc-4.8" ]; then
        local gcc_file="gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux.tar.xz"
        local gcc_dir="gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux"
        
        # Download GCC 4.8 if not already present
        if [ ! -f "$gcc_file" ]; then
            log_message "INFO" "Downloading GCC 4.8"
            wget "$GCC_48_URL" || handle_error "Failed to download GCC 4.8" "fatal"
        fi

        # Extract GCC 4.8 if not already extracted
        if [ ! -d "$gcc_dir" ]; then
            log_message "INFO" "Extracting GCC 4.8"
            tar -xaf "$gcc_file" || handle_error "Failed to extract GCC 4.8" "fatal"
        fi

        COMPILER_PATH="$CURRENT_PATH/$gcc_dir/bin/arm-linux-gnueabihf-"

    elif [ "$compiler" == "gcc-4.9" ]; then
        local gcc_file="gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz"
        local gcc_dir="gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf"
        
        # Download GCC 4.9 if not already present
        if [ ! -f "$gcc_file" ]; then
            log_message "INFO" "Downloading GCC 4.9"
            wget "$GCC_49_URL" || handle_error "Failed to download GCC 4.9" "fatal"
        fi

        # Extract GCC 4.9 if not already extracted
        if [ ! -d "$gcc_dir" ]; then
            log_message "INFO" "Extracting GCC 4.9"
            tar -xaf "$gcc_file" || handle_error "Failed to extract GCC 4.9" "fatal"
        fi

        COMPILER_PATH="$CURRENT_PATH/$gcc_dir/bin/arm-linux-gnueabihf-"

    elif [ "$compiler" == "arm-eabi-4.6" ]; then
        # Clone ARM EABI 4.6 if not already present
        if [ ! -d "arm-eabi-4.6" ]; then
            log_message "INFO" "Cloning ARM EABI 4.6"
            git clone -b kitkat-release --depth 1 "$ARM_EABI_REPO" || handle_error "Failed to clone ARM EABI 4.6 repository" "fatal"
        fi

        COMPILER_PATH="$CURRENT_PATH/arm-eabi-4.6/bin/arm-eabi-"

    else
        log_message "ERROR" "Unknown compiler: $compiler"
        zenity --error --text "Unknown compiler"
        handle_error "Unknown compiler selected: $compiler" "fatal"
    fi
    
    # Verify compiler exists and is executable
    if [ ! -f "${COMPILER_PATH}gcc" ]; then
        handle_error "Compiler executable not found: ${COMPILER_PATH}gcc" "fatal"
    fi
    
    log_message "INFO" "Using compiler at: $COMPILER_PATH"
}

#-----------------------------------------------------------------------
# initrd Setup Function
#-----------------------------------------------------------------------

# setup_initrd()
#
# Sets up the initial RAM disk (initrd) which is required for the kernel
# boot process. This function clones the initrd repository if needed and 
# builds the initrd image.
#
# Parameters:
#   None
#
# Returns:
#   None
#
# Dependencies:
#   - git: for cloning the initrd repository
#   - make: for building the initrd
#   - COMPILER_PATH: must be set by setup_compiler()
#
setup_initrd() {
    if [ ! -f "initrd.img" ]; then
        log_message "INFO" "Creating initrd image"
        
        # Clone initrd repository if needed
        if [ ! -d "initrd" ]; then
            git clone https://github.com/radxa/initrd.git || handle_error "Failed to clone initrd repository" "fatal"
        fi
        
        # First try building with host compiler
        make -C initrd || handle_error "Failed to build initrd" "warning"
    fi

    # If initrd.img still doesn't exist, try cross-compilation
    if [ ! -f "initrd.img" ]; then
        log_message "INFO" "Building initrd with cross-compiler"
        make -C initrd ARCH=arm CROSS_COMPILE="$COMPILER_PATH" || handle_error "Failed to build initrd with cross-compiler" "fatal"
        
        # Verify initrd was created successfully
        if [ ! -f "initrd.img" ]; then
            handle_error "Failed to create initrd.img" "fatal"
        fi
    else
        log_message "INFO" "initrd.img already exists"
    fi
}

#-----------------------------------------------------------------------
# Kernel Configuration Function
#-----------------------------------------------------------------------

# setup_kernel_config()
#
# Sets up kernel configuration by either copying the default configuration
# or asking the user if they want to restore the default configuration.
# This creates or updates the .config file in the kernel source directory.
#
# Parameters:
#   None
#
# Returns:
#   0 on success, non-zero on failure
#
setup_kernel_config() {
    # Check if default config exists
    check_file "$PROJECT_ROOT/$DEFAULT_KERNEL_CONFIG" "Default kernel configuration not found" "fatal" || return 1
    
    # Copy default config if not already done
    if [ ! -f "config_copied" ]; then
        log_message "INFO" "Copying default kernel configuration"
        rm -f "$PROJECT_ROOT/sys/$KERNEL_DIR/.config" 2>/dev/null
        
        cp "$PROJECT_ROOT/$DEFAULT_KERNEL_CONFIG" "$PROJECT_ROOT/sys/$KERNEL_DIR/.config" || \
            handle_error "Failed to copy default kernel configuration" "fatal"
            
        touch config_copied || handle_error "Failed to create config_copied marker" "warning"
    fi

    # Ask if the user wants to restore default config
    if zenity --question --title="Return Default Config" --text="Would you like to return to default configurations?" --no-wrap; then
        log_message "INFO" "Restoring default kernel configuration"
        cp "$PROJECT_ROOT/$DEFAULT_KERNEL_CONFIG" "$PROJECT_ROOT/sys/$KERNEL_DIR/.config" || \
            handle_error "Failed to restore default kernel configuration" "fatal"
    else
        log_message "INFO" "Keeping previous kernel configuration"
    fi
}

#-----------------------------------------------------------------------
# Kernel Build Function
#-----------------------------------------------------------------------

# build_kernel(config_gui)
#
# Performs the actual kernel build process:
# 1. Cleans the kernel build directory
# 2. Configures the kernel (optional GUI configuration)
# 3. Builds the kernel image
# 4. Optionally allows rebuilding with a different compiler
# 5. Installs kernel modules
#
# Parameters:
#   $1 - config_gui: The GUI configuration tool to use (e.g., menuconfig, xconfig)
#
# Returns:
#   None, but exits on fatal errors
#
# Environment required:
#   COMPILER_PATH - Set by setup_compiler()
#
build_kernel() {
    local config_gui="$1"
    
    cd "$PROJECT_ROOT/sys/$KERNEL_DIR" || handle_error "Failed to change to kernel directory" "fatal"
    
    # Clean the kernel build directory
    log_message "INFO" "Cleaning kernel build directory"
    execute_command "make clean" "Cleaning kernel build directory" || handle_error "Failed to clean kernel build directory" "warning"
    
    # Configure the kernel (using the specified configuration GUI)
    log_message "INFO" "Configuring kernel"
    execute_command "make $config_gui" "Configuring kernel with $config_gui" || handle_error "Failed to configure kernel with $config_gui" "fatal"
    
    # Build the kernel image
    log_message "INFO" "Building kernel image"
    execute_command "make -j2 ARCH=arm CROSS_COMPILE=\"$COMPILER_PATH\" kernel.img" "Building kernel image" || handle_error "Failed to build kernel image" "fatal"
    
    # Check if kernel image was built successfully
    if [ ! -f "arch/arm/boot/Image" ]; then
        handle_error "Kernel Image was not built" "fatal"
    fi
    
    # Ask if user wants to rebuild with a different compiler
    while true; do
        if zenity --question --title=" " --text="Click Yes if you want to rebuild kernel.img / Click No to continue" --no-wrap; then
            # Allow compiler reselection
            local ans=$(zenity --list --text "Choose a cross compiler" --radiolist --column "Pick" --column "Compiler" TRUE "arm-eabi-4.6" FALSE "default" FALSE "gcc-4.8" FALSE "gcc-4.9")
            
            if [ -z "$ans" ]; then
                log_message "WARN" "No compiler selected, using previous compiler"
            else
                log_message "INFO" "Rebuilding with compiler: $ans"
                setup_compiler "$ans"
            fi
            
            # Clean, configure, and rebuild the kernel
            execute_command "make clean" "Cleaning kernel build directory for rebuild" || handle_error "Failed to clean kernel build directory for rebuild" "warning"
            execute_command "make $config_gui" "Reconfiguring kernel" || handle_error "Failed to reconfigure kernel" "fatal"
            execute_command "make -j2 ARCH=arm CROSS_COMPILE=\"$COMPILER_PATH\" kernel.img" "Rebuilding kernel image" || handle_error "Failed to rebuild kernel image" "fatal"
        else
            log_message "INFO" "Continuing with current build"
            break
        fi
    done
    
    # Create modules directory and install modules
    ensure_directory "$PROJECT_ROOT/sys/$KERNEL_DIR/modules"
    
    # Build and install kernel modules
    log_message "INFO" "Installing kernel modules"
    execute_command "make ARCH=arm CROSS_COMPILE=\"$COMPILER_PATH\" INSTALL_MOD_PATH=./modules modules modules_install" "Installing kernel modules" || handle_error "Failed to install kernel modules" "warning"
    
    cd "$PROJECT_ROOT" || handle_error "Failed to change back to project root" "warning"
}

#-----------------------------------------------------------------------
# Boot Image Creation Function
#-----------------------------------------------------------------------

# create_boot_image()
#
# Creates a bootable image that can be flashed to the device.
# This combines the kernel Image with the initrd to create
# a boot-linux.img file.
#
# Parameters:
#   None
#
# Returns:
#   0 on success, non-zero on failure
#
# Dependencies:
#   - mkbootimg: for creating the bootable image
#
create_boot_image() {
    log_message "INFO" "Creating boot image"
    
    # Check if mkbootimg is available
    check_command mkbootimg "mkbootimg" "fatal" || return 1
    
    # Verify required files exist
    check_file "$PROJECT_ROOT/sys/$KERNEL_DIR/arch/arm/boot/Image" "Kernel Image not found" "fatal" || return 1
    check_file "$PROJECT_ROOT/sys/initrd.img" "initrd image not found" "fatal" || return 1
    
    # Ensure the target directory exists
    ensure_directory "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR"
    
    # Create boot image by combining kernel and initrd
    mkbootimg --kernel "$PROJECT_ROOT/sys/$KERNEL_DIR/arch/arm/boot/Image" \
              --ramdisk "$PROJECT_ROOT/sys/initrd.img" \
              -o "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/boot-linux.img" || \
              handle_error "Failed to create boot image" "fatal"
    
    # Verify the boot image was created
    check_file "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/boot-linux.img" "Boot image not created" "fatal" || return 1
    
    # Save a backup of the kernel configuration
    cp "$PROJECT_ROOT/sys/$KERNEL_DIR/.config" "$PROJECT_ROOT/last_config_backup" || \
        handle_error "Failed to save configuration backup" "warning"
    
    log_message "INFO" "Boot image created successfully"
    
    # Highlight the kernel and boot image artifacts
    highlight_output "KERNEL" "Raw Kernel Image" "$PROJECT_ROOT/sys/$KERNEL_DIR/arch/arm/boot/Image" "The uncompressed kernel image"
    highlight_output "KERNEL" "Boot Linux Image" "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/boot-linux.img" "Combined kernel and initrd ready for flashing"
    highlight_output "KERNEL" "Saved Kernel Config" "$PROJECT_ROOT/last_config_backup" "Backup of the kernel configuration"
}

# Export functions - Makes these functions available to parent scripts
export -f compile_kernel 