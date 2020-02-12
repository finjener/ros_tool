#!/bin/bash

#########################################################################
# Buildroot Module for ROS Tool
#########################################################################
#
# This module handles the setup, configuration, and build process for
# Buildroot, which is used to generate the root filesystem for the 
# embedded Linux system. 
#
# Buildroot is a tool that simplifies the process of building a complete
# Linux system for embedded applications. It generates a cross-compilation
# toolchain, a root filesystem, a Linux kernel, and a bootloader for the
# target system.
#
# This module provides functionality to:
# 1. Download and extract Buildroot
# 2. Configure Buildroot for specific targets (Radxa, Raspberry Pi 3)
# 3. Build the Buildroot system
# 4. Manage existing Buildroot installations
#
#########################################################################

# Load shared functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"
source "$PROJECT_ROOT/scripts/utils.sh"

#-----------------------------------------------------------------------
# Main Buildroot Setup Function
#-----------------------------------------------------------------------

# setup_buildroot(target)
#
# Main entry point for Buildroot setup and configuration.
# This function handles the entire process of setting up Buildroot
# for a specific target platform.
#
# Parameters:
#   $1 - target: The target hardware platform ('radxa' or 'rasp3')
#
# Returns:
#   0 on success, non-zero on failure
#
# Dependencies:
#   - make: for building Buildroot
#   - wget: for downloading Buildroot sources
#   - zenity: for GUI interactions (if available)
#
setup_buildroot() {
    local target="$1"  # 'radxa' or 'rasp3'
    
    # Validate target
    if [[ "$target" != "radxa" && "$target" != "rasp3" ]]; then
        handle_error "Invalid target for Buildroot: $target. Must be 'radxa' or 'rasp3'" "fatal"
        return 1
    fi
    
    log_message "INFO" "Setting up Buildroot for target: $target"
    
    # Check for required tools
    check_command make "build-essential" "fatal" || return 1
    check_command wget "wget" "fatal" || return 1
    
    # Prompt user to select buildroot version
    local buildroot_version="${BUILDROOT_VERSIONS[0]}"
    local buildroot_year="${BUILDROOT_VERSIONS[1]}"
    
    local ans=$(zenity --list --text "Choose a buildroot option" --radiolist --column "Pick" --column "version" TRUE "$buildroot_version") || {
        handle_error "Failed to get buildroot version selection from zenity" "warning"
        log_message "WARN" "Using default buildroot version: $buildroot_version"
    }
    
    if [ -z "$ans" ]; then
        log_message "WARN" "No buildroot version selected, using default: $buildroot_version"
    elif [ "$ans" == "$buildroot_version" ]; then
        buildroot_version="$ans"
    else
        log_message "ERROR" "Unknown Buildroot version selected: $ans"
        return 1
    fi
    
    # Verify default config exists before proceeding
    local config_file="../ros_tool/conf/$target-${buildroot_version}_default_defconfig"
    check_file "$config_file" "Default Buildroot configuration not found for $target" "fatal" || return 1
    
    # Check if target directory exists
    if [ ! -d "../$target" ]; then
        log_message "INFO" "Creating directory for $target"
        mkdir -p "../$target" || {
            handle_error "Failed to create directory for $target" "fatal"
            return 1
        }
    fi
    
    cd "../$target" || {
        handle_error "Failed to change to target directory: ../$target" "fatal"
        return 1
    }
    
    # Configure and build Buildroot - handle existing or new installation
    if [ -d "$buildroot_version" ]; then
        handle_existing_buildroot "$target" "$buildroot_version" || {
            handle_error "Failed to handle existing Buildroot for $target" "fatal"
            cd "$PROJECT_ROOT" 2>/dev/null
            return 1
        }
    else
        download_and_setup_buildroot "$target" "$buildroot_version" || {
            handle_error "Failed to download and setup Buildroot for $target" "fatal"
            cd "$PROJECT_ROOT" 2>/dev/null
            return 1
        }
    fi
    
    # Ensure we return to the project root, even if there was an error
    cd "$PROJECT_ROOT" || {
        handle_error "Failed to return to project root directory" "warning"
        return 1
    }
    
    log_message "INFO" "Buildroot setup completed for target: $target"
    return 0
}

#-----------------------------------------------------------------------
# Existing Buildroot Management
#-----------------------------------------------------------------------

# handle_existing_buildroot(target, buildroot_version)
#
# Handles an existing Buildroot installation, offering to reset
# to default configuration and running the build process.
#
# Parameters:
#   $1 - target: The target hardware platform ('radxa' or 'rasp3')
#   $2 - buildroot_version: The version of Buildroot to use
#
# Returns:
#   0 on success, non-zero on failure
#
handle_existing_buildroot() {
    local target="$1"
    local buildroot_version="$2"
    local return_code=0
    
    # Validate inputs
    if [ -z "$target" ] || [ -z "$buildroot_version" ]; then
        handle_error "Missing required parameters for handle_existing_buildroot" "fatal"
        return 1
    fi
    
    # Ensure buildroot directory exists
    if [ ! -d "./${buildroot_version}" ]; then
        handle_error "Buildroot directory not found: ./${buildroot_version}" "fatal"
        return 1
    fi
    
    # Check if makefile exists
    if [ ! -f "./${buildroot_version}/Makefile" ]; then
        handle_error "Buildroot Makefile not found in ./${buildroot_version}" "fatal"
        return 1
    fi
    
    # Ask user about default config
    zenity --question --title=" " --text="Say Yes If you want to return default buildroot config? / Say No continue with previous?" --no-wrap
    case $? in
        [0]* ) 
            log_message "INFO" "Using default Buildroot configuration"
            cp "../ros_tool/conf/$target-${buildroot_version}_default_defconfig" "./${buildroot_version}/.config" || {
                handle_error "Failed to copy default configuration for $target" "fatal"
                return 1
            }
            ;;
        [1]* ) 
            log_message "INFO" "Keeping previous Buildroot configuration"
            ;;
        * ) 
            log_message "WARN" "Invalid response, keeping previous configuration"
            ;;
    esac
    
    # Verify xconfig is available
    if ! make --directory="./${buildroot_version}/" -n xconfig &>/dev/null; then
        handle_error "xconfig target not available in Buildroot makefile" "fatal"
        return 1
    fi
    
    # Launch xconfig for user configuration of Buildroot
    log_message "INFO" "Starting Buildroot configuration"
    execute_command "make --directory=\"./${buildroot_version}/\" xconfig" "Running Buildroot configuration (xconfig)" || {
        handle_error "Failed to run Buildroot configuration (xconfig)" "fatal"
        return 1
    }
    
    # Build Buildroot with the configured settings
    log_message "INFO" "Building Buildroot"
    execute_command "make --directory=\"./${buildroot_version}/\"" "Building Buildroot" || {
        handle_error "Failed to build Buildroot" "fatal"
        return 1
    }
    
    # Highlight important Buildroot outputs
    highlight_output "BUILDROOT" "Buildroot Output Directory" "$PROJECT_ROOT/sys/${buildroot_version}/output" "Contains all build artifacts"
    highlight_output "BUILDROOT" "Compiled Images" "$PROJECT_ROOT/sys/${buildroot_version}/output/images" "Contains the root filesystem images, kernels, etc."
    highlight_output "BUILDROOT" "Target Directory" "$PROJECT_ROOT/sys/${buildroot_version}/output/target" "Contains the complete root filesystem"
    
    # Offer to rebuild in case user wants to make changes
    offer_rebuild_buildroot "$target" "$buildroot_version"
    return_code=$?
    
    return $return_code
}

#-----------------------------------------------------------------------
# Fresh Buildroot Installation
#-----------------------------------------------------------------------

# download_and_setup_buildroot(target, buildroot_version)
#
# Downloads and sets up a fresh Buildroot installation.
# This function handles downloading the Buildroot archive,
# extracting it, applying the target-specific configuration,
# and building Buildroot.
#
# Parameters:
#   $1 - target: The target hardware platform ('radxa' or 'rasp3')
#   $2 - buildroot_version: The version of Buildroot to download
#
# Returns:
#   0 on success, non-zero on failure
#
# Dependencies:
#   - wget: for downloading Buildroot
#   - tar: for extracting the Buildroot archive
#
download_and_setup_buildroot() {
    local target="$1"
    local buildroot_version="$2"
    
    # Validate inputs
    if [ -z "$target" ] || [ -z "$buildroot_version" ]; then
        handle_error "Missing required parameters for download_and_setup_buildroot" "fatal"
        return 1
    fi
    
    # Check for wget command
    check_command wget "wget" "fatal" || return 1
    
    # Download Buildroot archive from official site
    log_message "INFO" "Downloading Buildroot $buildroot_version"
    wget "https://buildroot.org/downloads/${buildroot_version}.tar.gz" || {
        handle_error "Failed to download Buildroot archive" "fatal"
        return 1
    }
    
    # Extract Buildroot archive
    log_message "INFO" "Extracting Buildroot"
    tar zxvf "${buildroot_version}.tar.gz" > /dev/null || {
        handle_error "Failed to extract Buildroot archive" "fatal"
        return 1
    }
    
    # Verify extraction was successful
    if [ ! -d "${buildroot_version}" ]; then
        handle_error "Failed to find extracted Buildroot directory: ${buildroot_version}" "fatal"
        return 1
    fi
    
    # Verify directory has Makefile
    if [ ! -f "${buildroot_version}/Makefile" ]; then
        handle_error "Extracted Buildroot directory does not contain a Makefile" "fatal"
        return 1
    fi
    
    # Apply target-specific configuration
    log_message "INFO" "Applying configuration for $target"
    cp "../ros_tool/conf/$target-${buildroot_version}_default_defconfig" "${buildroot_version}/.config" || {
        handle_error "Failed to copy default configuration for $target" "fatal"
        return 1
    }
    
    # Verify xconfig is available
    if ! make --directory="./${buildroot_version}/" -n xconfig &>/dev/null; then
        handle_error "xconfig target not available in Buildroot makefile" "fatal"
        return 1
    fi
    
    # Launch xconfig for user configuration of Buildroot
    log_message "INFO" "Starting Buildroot configuration"
    execute_command "make --directory=\"./${buildroot_version}/\" xconfig" "Running Buildroot configuration (xconfig)" || {
        handle_error "Failed to run Buildroot configuration (xconfig)" "fatal"
        return 1
    }
    
    # Build Buildroot
    log_message "INFO" "Building Buildroot"
    execute_command "make --directory=\"./${buildroot_version}/\"" "Building Buildroot" || {
        handle_error "Failed to build Buildroot for first-time setup" "fatal"
        return 1
    }
    
    # Highlight important Buildroot outputs
    highlight_output "BUILDROOT" "Buildroot Output Directory" "$PROJECT_ROOT/sys/${buildroot_version}/output" "Contains all build artifacts"
    highlight_output "BUILDROOT" "Compiled Images" "$PROJECT_ROOT/sys/${buildroot_version}/output/images" "Contains the root filesystem images, kernels, etc."
    highlight_output "BUILDROOT" "Target Directory" "$PROJECT_ROOT/sys/${buildroot_version}/output/target" "Contains the complete root filesystem"
    
    log_message "INFO" "Buildroot setup completed successfully"
    
    return 0
}

#-----------------------------------------------------------------------
# Rebuild Function
#-----------------------------------------------------------------------

# offer_rebuild_buildroot(target, buildroot_version)
#
# Offers the user the option to rebuild Buildroot with potentially
# different configuration settings. This provides a way to iterate
# on Buildroot configuration without restarting the entire process.
#
# Parameters:
#   $1 - target: The target hardware platform ('radxa' or 'rasp3')
#   $2 - buildroot_version: The version of Buildroot being used
#
# Returns:
#   0 on success, non-zero on failure
#
offer_rebuild_buildroot() {
    local target="$1"
    local buildroot_version="$2"
    local return_code=0
    
    # Validate inputs
    if [ -z "$target" ] || [ -z "$buildroot_version" ]; then
        handle_error "Missing required parameters for offer_rebuild_buildroot" "warning"
        return 1
    fi
    
    while true; do
        log_message "INFO" "Checking if rebuild is needed"
        
        # Ask user if they want to rebuild Buildroot
        zenity --question --title=" " --text="Click Yes If you want to return make buildroot again? / Click No continue?" --no-wrap
        case $? in
            [0]* )
                # Ask user if they want to reset to default configuration
                zenity --question --title=" " --text="Click Yes If you want to return default buildroot config? / Click No continue with previous?" --no-wrap
                case $? in
                    [0]* ) 
                        log_message "INFO" "Using default Buildroot configuration"
                        cp "../ros_tool/conf/$target-${buildroot_version}_default_defconfig" "./${buildroot_version}/.config" || {
                            handle_error "Failed to copy default configuration for rebuild" "warning"
                            return_code=1
                            continue
                        }
                        ;;
                    [1]* ) 
                        log_message "INFO" "Keeping previous Buildroot configuration"
                        ;;
                    * ) 
                        log_message "WARN" "Invalid response, keeping previous configuration"
                        ;;
                esac 
                
                # Reconfigure Buildroot using xconfig
                log_message "INFO" "Reconfiguring Buildroot"
                execute_command "make --directory=\"./${buildroot_version}/\" xconfig" "Reconfiguring Buildroot" || {
                    handle_error "Failed to reconfigure Buildroot" "warning"
                    return_code=1
                    continue
                }
                
                # Rebuild Buildroot with new configuration
                log_message "INFO" "Rebuilding Buildroot"
                execute_command "make --directory=\"./${buildroot_version}/\"" "Rebuilding Buildroot" || {
                    handle_error "Failed to rebuild Buildroot" "warning"
                    return_code=1
                    continue
                }
                ;;
            [1]* )
                log_message "INFO" "Proceeding without rebuilding"
                break
                ;;
            * ) 
                log_message "WARN" "Invalid response, proceeding without rebuilding"
                break
                ;;
        esac
    done
    
    return $return_code
}

# Export functions - Makes these functions available to parent scripts
export -f setup_buildroot 