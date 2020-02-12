#!/bin/bash

#########################################################################
# Clean Module for ROS Tool
#########################################################################
#
# This module provides functionality for cleaning various build artifacts
# generated during the ROS Tool build process. It helps maintain a clean
# workspace and resolves issues that might arise from stale build files.
#
# The module provides targeted cleaning functions for individual components
# (kernel, buildroot, rootfs, flash) as well as a comprehensive cleaning
# function that can perform standard or deep cleaning of all artifacts.
#
# The clean operations are designed to be safe and provide appropriate
# error handling, with warnings for operations that fail but are not
# critical for continuing with the build process.
#
#########################################################################
#
# DESCRIPTION:
#   Module containing functions for cleaning various build artifacts.
#   Used by both run.sh and clean.sh.
#
# FUNCTIONS:
#   clean_kernel()     - Clean kernel build artifacts
#   clean_buildroot()  - Clean buildroot artifacts for specified target
#   clean_rootfs()     - Clean rootfs artifacts and unmount filesystems
#   clean_flash()      - Clean flash artifacts (update images)
#   clean_all()        - Clean all artifacts, optionally perform deep cleaning
#
# PARAMETERS:
#   clean_buildroot <target>  - Target platform (radxa, rasp3)
#   clean_all <level>         - Cleaning level (normal, deep)
#
# USAGE:
#   This file is meant to be sourced by other scripts, not run directly.
#   Example:
#     source "$PROJECT_ROOT/scripts/clean.sh"
#     clean_kernel
#     clean_buildroot "radxa"
#     clean_all "deep"
#
#########################################################################

# Load shared functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/scripts/config.sh"
source "$PROJECT_ROOT/scripts/utils.sh"

#-----------------------------------------------------------------------
# Kernel Cleanup Function
#-----------------------------------------------------------------------

# clean_kernel()
#
# Cleans kernel build artifacts, including compiled objects,
# generated modules, and boot images.
#
# Parameters:
#   None
#
# Returns:
#   0 on success, non-zero on failure
#
# Notes:
#   This function runs 'make clean' in the kernel directory if available,
#   and removes the modules directory and generated boot image.
#
clean_kernel() {
    log_message "INFO" "Cleaning kernel build artifacts"
    
    if [ -d "$PROJECT_ROOT/sys/$KERNEL_DIR" ]; then
        log_message "INFO" "Cleaning kernel build directory"
        cd "$PROJECT_ROOT/sys/$KERNEL_DIR" || {
            handle_error "Failed to change to kernel directory" "warning"
            return 1
        }
        
        if [ -f "Makefile" ]; then
            make clean || handle_error "Failed to clean kernel build directory" "warning"
        else
            log_message "WARN" "Kernel Makefile not found, skipping make clean"
        fi
        
        cd "$PROJECT_ROOT" || handle_error "Failed to return to project root" "warning"
    else
        log_message "INFO" "Kernel directory not found, nothing to clean"
    fi
    
    # Remove kernel modules
    if [ -d "$PROJECT_ROOT/sys/$KERNEL_DIR/modules" ]; then
        log_message "INFO" "Removing kernel modules"
        rm -rf "$PROJECT_ROOT/sys/$KERNEL_DIR/modules" || {
            handle_error "Failed to remove kernel modules directory" "warning"
            return 1
        }
    fi
    
    # Remove boot image
    if [ -f "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/boot-linux.img" ]; then
        log_message "INFO" "Removing boot image"
        rm -f "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/boot-linux.img" || {
            handle_error "Failed to remove boot image" "warning"
            return 1
        }
    fi
    
    log_message "INFO" "Kernel cleanup completed"
    return 0
}

#-----------------------------------------------------------------------
# Buildroot Cleanup Function
#-----------------------------------------------------------------------

# clean_buildroot(target)
#
# Cleans buildroot artifacts for the specified target.
# If no target is specified, cleans both radxa and rasp3 targets.
#
# Parameters:
#   $1 - target: Target platform ('radxa' or 'rasp3')
#
# Returns:
#   0 on success, non-zero on failure
#
# Notes:
#   This function runs 'make clean' in the buildroot directory for
#   the specified target if available.
#
clean_buildroot() {
    local target="$1"  # radxa or rasp3
    
    if [ -z "$target" ]; then
        # Clean both targets if none specified
        log_message "INFO" "No target specified, cleaning both radxa and rasp3"
        clean_buildroot "radxa"
        clean_buildroot "rasp3"
        return $?
    fi
    
    # Validate target
    if [[ "$target" != "radxa" && "$target" != "rasp3" ]]; then
        handle_error "Invalid target for buildroot cleaning: $target" "warning"
        return 1
    fi
    
    log_message "INFO" "Cleaning buildroot artifacts for target: $target"
    
    local buildroot_dir="../$target/${BUILDROOT_VERSIONS[0]}"
    
    if [ -d "$buildroot_dir" ]; then
        log_message "INFO" "Cleaning buildroot directory: $buildroot_dir"
        cd "$buildroot_dir" || {
            handle_error "Failed to change to buildroot directory: $buildroot_dir" "warning"
            return 1
        }
        
        if [ -f "Makefile" ]; then
            make clean || handle_error "Failed to clean buildroot directory" "warning"
        else
            log_message "WARN" "Buildroot Makefile not found, skipping make clean"
        fi
        
        cd "$PROJECT_ROOT" || handle_error "Failed to return to project root" "warning"
    else
        log_message "INFO" "Buildroot directory not found for $target, nothing to clean"
    fi
    
    log_message "INFO" "Buildroot cleanup completed for $target"
    return 0
}

#-----------------------------------------------------------------------
# Rootfs Cleanup Function
#-----------------------------------------------------------------------

# clean_rootfs()
#
# Cleans rootfs artifacts, including unmounting any mounted filesystems,
# removing mount points, and deleting rootfs image files.
#
# Parameters:
#   None
#
# Returns:
#   0 on success, non-zero on failure
#
# Notes:
#   This function requires sudo privileges to unmount filesystems
#   and remove mount points.
#
clean_rootfs() {
    log_message "INFO" "Cleaning rootfs artifacts"
    
    # Unmount any mounted rootfs
    if mount | grep -q "$PROJECT_ROOT/mnt-rootfs"; then
        log_message "INFO" "Unmounting rootfs"
        sudo umount "$PROJECT_ROOT/mnt-rootfs" || {
            handle_error "Failed to unmount rootfs. Are there open files?" "warning"
            # Try to force unmount if regular unmount fails
            log_message "WARN" "Attempting force unmount..."
            sudo umount -f "$PROJECT_ROOT/mnt-rootfs" || {
                handle_error "Forced unmount failed" "warning"
                return 1
            }
        }
    fi
    
    # Remove mount directory
    if [ -d "$PROJECT_ROOT/mnt-rootfs" ]; then
        log_message "INFO" "Removing mount directory"
        sudo rm -rf "$PROJECT_ROOT/mnt-rootfs" || {
            handle_error "Failed to remove mount directory" "warning"
            return 1
        }
    fi
    
    # Remove rootfs images
    log_message "INFO" "Removing rootfs images"
    rm -f "$PROJECT_ROOT/rootfs-*.img" 2>/dev/null || log_message "DEBUG" "No rootfs-*.img files to remove"
    rm -f "$PROJECT_ROOT/rootfs.tar" 2>/dev/null || log_message "DEBUG" "No rootfs.tar file to remove"
    
    # Check if the ROCKCHIP_LINUX_DIR exists before trying to remove files from it
    if [ -d "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR" ]; then
        rm -f "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/rootfs.img" 2>/dev/null || log_message "DEBUG" "No rootfs.img in $ROCKCHIP_LINUX_DIR to remove"
    else
        log_message "DEBUG" "Rockchip Linux directory not found, skipping cleanup there"
    fi
    
    log_message "INFO" "Rootfs cleanup completed"
    return 0
}

#-----------------------------------------------------------------------
# Flash Cleanup Function
#-----------------------------------------------------------------------

# clean_flash()
#
# Cleans flash artifacts, including update images.
#
# Parameters:
#   None
#
# Returns:
#   0 on success, non-zero on failure
#
# Notes:
#   This function removes the update.img file from the Rockchip tools
#   directory if it exists.
#
clean_flash() {
    log_message "INFO" "Cleaning flash artifacts"
    
    # Check if the ROCKCHIP_TOOLS_DIR exists before trying to remove files from it
    if [ ! -d "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR" ]; then
        log_message "WARN" "Rockchip tools directory not found: $PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR"
        return 0
    fi
    
    # Remove update image
    if [ -f "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR/update.img" ]; then
        log_message "INFO" "Removing update image"
        rm -f "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR/update.img" || {
            handle_error "Failed to remove update image" "warning"
            return 1
        }
    else
        log_message "DEBUG" "No update.img file to remove"
    fi
    
    log_message "INFO" "Flash cleanup completed"
    return 0
}

#-----------------------------------------------------------------------
# Complete Cleanup Function
#-----------------------------------------------------------------------

# clean_all(level)
#
# Performs a complete cleanup of all build artifacts.
# The cleanup level determines the thoroughness of the cleanup.
#
# Parameters:
#   $1 - level: Cleanup level ('normal' or 'deep')
#                'normal' - Remove build artifacts only
#                'deep'   - Remove build artifacts, sources, and downloaded files
#
# Returns:
#   0 on success, non-zero if any cleanup operation failed
#
# Notes:
#   Deep cleanup removes all sources and downloaded files,
#   requiring a complete rebuild for the next build operation.
#
clean_all() {
    local level="$1"  # deep or normal
    local success=0
    
    log_message "INFO" "Starting complete cleanup (level: $level)"
    
    # Validate cleanup level
    if [[ "$level" != "deep" && "$level" != "normal" ]]; then
        log_message "WARN" "Invalid cleanup level: $level. Using 'normal'"
        level="normal"
    fi
    
    # Clean all components
    clean_kernel
    success=$((success | $?))
    
    clean_buildroot
    success=$((success | $?))
    
    clean_rootfs
    success=$((success | $?))
    
    clean_flash
    success=$((success | $?))
    
    # Additional deep cleaning
    if [ "$level" == "deep" ]; then
        log_message "INFO" "Performing deep cleanup"
        
        # Remove all downloaded compilers
        log_message "INFO" "Removing downloaded compilers"
        rm -rf "$PROJECT_ROOT/gcc-linaro-*" 2>/dev/null || log_message "DEBUG" "No gcc-linaro-* files to remove"
        rm -rf "$PROJECT_ROOT/arm-eabi-*" 2>/dev/null || log_message "DEBUG" "No arm-eabi-* files to remove"
        
        # Remove kernel sources
        if [ -d "$PROJECT_ROOT/sys" ]; then
            log_message "INFO" "Removing kernel sources"
            rm -rf "$PROJECT_ROOT/sys" || {
                handle_error "Failed to remove kernel sources directory" "warning"
                success=1
            }
        fi
        
        # Remove temporary files
        log_message "INFO" "Removing temporary files"
        find "$PROJECT_ROOT" -name "*.tmp" -delete 2>/dev/null || log_message "DEBUG" "No .tmp files to remove"
        find "$PROJECT_ROOT" -name "*.o" -delete 2>/dev/null || log_message "DEBUG" "No .o files to remove"
        find "$PROJECT_ROOT" -name "*.ko" -delete 2>/dev/null || log_message "DEBUG" "No .ko files to remove"
        
        log_message "INFO" "Deep cleanup completed"
    fi
    
    # Reset config_copied marker
    if [ -f "$PROJECT_ROOT/config_copied" ]; then
        log_message "INFO" "Removing config_copied marker"
        rm -f "$PROJECT_ROOT/config_copied" || log_message "WARN" "Failed to remove config_copied marker"
    fi
    
    if [ $success -eq 0 ]; then
        log_message "INFO" "All cleanup operations completed successfully"
    else
        log_message "WARN" "Some cleanup operations reported errors"
    fi
    
    return $success
}

# Export functions - Makes these functions available to parent scripts
export -f clean_kernel
export -f clean_buildroot
export -f clean_rootfs
export -f clean_flash
export -f clean_all 