#!/bin/bash

#########################################################################
# Flash Module for ROS Tool
#########################################################################
#
# This module handles the packaging of firmware components and flashing 
# them to target devices. It specifically supports Rockchip-based devices 
# by creating a complete update.img file from individual components 
# (bootloader, kernel, rootfs) and optionally flashing it to a connected 
# device.
#
# The flashing process follows these steps:
# 1. Verify all required components and tools are available
# 2. Package the components into an update.img file
# 3. Optionally flash the update.img to a connected device
#
# This module requires the device to be in maskrom mode for flashing,
# which typically involves holding specific buttons while powering on
# the device.
#
#########################################################################

# Load shared functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"
source "$PROJECT_ROOT/scripts/utils.sh"

#-----------------------------------------------------------------------
# Main Packaging and Flashing Function
#-----------------------------------------------------------------------

# package_and_flash(should_flash)
#
# Main entry point for firmware packaging and optional device flashing.
# This function coordinates the process of creating an update.img file 
# from the bootloader, kernel, and rootfs components and optionally
# flashing it to a connected device.
#
# Parameters:
#   $1 - should_flash: Set to "-flash" to flash the device after packaging,
#                      or empty to only package without flashing
#
# Returns:
#   0 on success, non-zero on failure
#
# Dependencies:
#   - mkupdate.sh: Script for creating the update.img
#   - upgrade_tool: Tool for flashing the update.img to the device
#   - sudo: Required for device flashing with elevated privileges
#
package_and_flash() {
    local should_flash="$1"  # "-flash" to flash, empty to just package
    local return_code=0
    
    # Check if rockchip-tools directory exists
    if [ ! -d "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR" ]; then
        handle_error "Rockchip tools directory not found: $PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR" "fatal"
        return 1
    fi
    
    # Check for required scripts and tools
    if [ ! -f "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR/mkupdate.sh" ]; then
        handle_error "mkupdate.sh script not found" "fatal"
        return 1
    fi
    
    # If flashing is requested, check for upgrade_tool
    if [ "$should_flash" == "-flash" ] && [ ! -f "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR/upgrade_tool" ]; then
        handle_error "upgrade_tool not found but required for flashing" "fatal"
        return 1
    fi
    
    log_message "INFO" "Packaging firmware image"
    
    # Change to rockchip-tools directory
    cd "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR/" || {
        handle_error "Failed to change to rockchip-tools directory" "fatal"
        return 1
    }
    
    # Make sure scripts are executable
    chmod +x ./mkupdate.sh 2>/dev/null || log_message "WARN" "Failed to make mkupdate.sh executable"
    if [ "$should_flash" == "-flash" ]; then
        chmod +x ./upgrade_tool 2>/dev/null || log_message "WARN" "Failed to make upgrade_tool executable"
    fi
    
    # Create update.img
    create_update_img || {
        handle_error "Failed to create update.img" "fatal"
        cd "$PROJECT_ROOT" 2>/dev/null
        return 1
    }
    
    # Verify update.img was created
    if [ ! -f "./update.img" ]; then
        handle_error "update.img file was not created" "fatal"
        cd "$PROJECT_ROOT" 2>/dev/null
        return 1
    fi
    
    # Flash if requested
    if [ "$should_flash" == "-flash" ]; then
        flash_device || {
            handle_error "Failed to flash device" "fatal"
            return_code=1
        }
    fi
    
    # Return to project root
    cd "$PROJECT_ROOT" || {
        handle_error "Failed to return to project root directory" "warning"
        return 1
    }
    
    if [ $return_code -eq 0 ]; then
        log_message "INFO" "Packaging/flashing process completed successfully"
    else
        log_message "WARN" "Packaging/flashing process completed with errors"
    fi
    
    return $return_code
}

#-----------------------------------------------------------------------
# Firmware Packaging Function
#-----------------------------------------------------------------------

# create_update_img()
#
# Creates an update.img file containing the bootloader, kernel image,
# and root filesystem. This image can be flashed to the target device.
#
# Parameters:
#   None
#
# Returns:
#   0 on success, non-zero on failure
#
# Dependencies:
#   - mkupdate.sh: Script provided by Rockchip for creating update images
#   - package-file: Configuration file for mkupdate.sh
#   - Bootloader binary (specified in config as BOOTLOADER_BIN)
#   - Linux/boot-linux.img: Kernel image
#   - Linux/rootfs.img: Root filesystem image
#
create_update_img() {
    log_message "INFO" "Creating update.img file"
    
    # Check if package-file exists (required for mkupdate.sh)
    if [ ! -f "./package-file" ]; then
        handle_error "package-file not found, required for creating update.img" "fatal"
        return 1
    fi
    
    # Check if bootloader exists
    if [ ! -f "./$BOOTLOADER_BIN" ]; then
        handle_error "Bootloader file not found: $BOOTLOADER_BIN" "fatal"
        return 1
    fi
    
    # Check if Linux directory exists with required files
    if [ ! -d "./Linux" ]; then
        handle_error "Linux directory not found" "fatal"
        return 1
    fi
    
    if [ ! -f "./Linux/boot-linux.img" ]; then
        handle_error "Boot image not found: Linux/boot-linux.img" "fatal"
        return 1
    fi
    
    if [ ! -f "./Linux/rootfs.img" ]; then
        handle_error "Rootfs image not found: Linux/rootfs.img" "fatal"
        return 1
    fi
    
    # Remove old update.img if it exists
    if [ -f "./update.img" ]; then
        log_message "INFO" "Removing old update.img"
        rm -f "./update.img" || {
            handle_error "Failed to remove old update.img" "warning"
            # Continue despite warning
        }
    fi
    
    # Run the script to create the update.img
    log_message "INFO" "Creating update.img from boot-linux.img and rootfs.img"
    bash ./mkupdate.sh || {
        handle_error "Failed to create update.img" "fatal"
        return 1
    }
    
    # Verify the update.img was created
    check_file "./update.img" "Update image not created" "fatal" || return 1
    
    # Highlight the update image
    highlight_output "FLASH" "Update Image" "$PROJECT_ROOT/rockchip-tools/update.img" "Complete system image ready for flashing"
    
    log_message "INFO" "Update image created successfully"
    return 0
}

#-----------------------------------------------------------------------
# Device Flashing Function
#-----------------------------------------------------------------------

# flash_device()
#
# Flashes the update.img to a connected device that is in maskrom mode.
# The function guides the user to put the device in the correct mode
# and then performs the flashing operation.
#
# Parameters:
#   None
#
# Returns:
#   0 on success, non-zero on failure
#
# Dependencies:
#   - upgrade_tool: Rockchip tool for flashing devices
#   - sudo: Required for access to USB devices
#   - update.img: Firmware image to flash
#
flash_device() {
    log_message "INFO" "Preparing to flash device"
    
    # Check if required tools exist
    if [ ! -f "./upgrade_tool" ]; then
        handle_error "upgrade_tool not found" "fatal"
        return 1
    fi
    
    if [ ! -f "./update.img" ]; then
        handle_error "update.img not found" "fatal"
        return 1
    fi
    
    # Verify upgrade_tool is executable
    if [ ! -x "./upgrade_tool" ]; then
        log_message "WARN" "upgrade_tool is not executable, attempting to fix"
        chmod +x ./upgrade_tool || {
            handle_error "Failed to make upgrade_tool executable" "fatal"
            return 1
        }
    fi
    
    # Prompt user to put device in maskrom mode
    log_message "INFO" "Device must be in maskrom mode for flashing"
    read -p "Put radxa rock pro in maskrom mode, then press Enter: " yn
    
    # List devices in maskrom mode
    log_message "INFO" "Looking for devices in maskrom mode"
    sudo ./upgrade_tool lf || {
        handle_error "Failed to list devices in maskrom mode" "fatal"
        return 1
    }
    
    # Flash the update.img to the device
    log_message "INFO" "Flashing update.img to device"
    sudo ./upgrade_tool uf update.img || {
        handle_error "Failed to flash update.img to device" "fatal"
        return 1
    }
    
    log_message "INFO" "Flashing completed successfully"
    highlight_output "FLASH" "Flashed Image" "$PROJECT_ROOT/rockchip-tools/update.img" "This image was successfully flashed to the device"
    
    return 0
}

# Export functions - Makes these functions available to parent scripts
export -f package_and_flash 