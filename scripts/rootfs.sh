#!/bin/bash

#########################################################################
# Rootfs Generation Module for ROS Tool
#########################################################################
#
# This module handles the generation of the root filesystem (rootfs) image
# for embedded Linux systems. It creates an ext4 filesystem, extracts
# the Buildroot-generated rootfs into it, and installs kernel modules
# and firmware.
#
# The rootfs generation process follows these steps:
# 1. Clean up any existing mounts and old files
# 2. Create a new ext4 image file of the specified size
# 3. Mount the image file
# 4. Extract the Buildroot-generated rootfs tarball to the mounted image
# 5. Install kernel modules and firmware
# 6. Unmount and finalize the image
#
#########################################################################

# Load shared functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"
source "$PROJECT_ROOT/scripts/utils.sh"

#-----------------------------------------------------------------------
# Main Rootfs Generation Function
#-----------------------------------------------------------------------

rootfs_image_generate() {
    local buildroot_year="$1"
    local buildroot_path="$2"
    local return_code=0
    
    # Validate inputs
    if [ -z "$buildroot_year" ] || [ -z "$buildroot_path" ]; then
        handle_error "Missing required parameters for rootfs_image_generate" "fatal"
        return 1
    fi
    
    # Check if buildroot path exists
    if [ ! -d "$buildroot_path" ]; then
        handle_error "Buildroot path does not exist: $buildroot_path" "fatal"
        return 1
    fi
    
    # Check if rootfs tarball exists
    if [ ! -f "$buildroot_path/output/images/rootfs.tar" ]; then
        handle_error "Rootfs tarball not found: $buildroot_path/output/images/rootfs.tar" "fatal"
        return 1
    fi
    
    # Clean up old mounts if any
    cleanup_mounts || {
        handle_error "Failed to cleanup existing mounts" "fatal"
        return 1
    }
    
    # Clean up old files
    cleanup_old_files "$buildroot_year" || {
        handle_error "Failed to cleanup old files" "warning"
        # Continue despite warning
    }
    
    # Create mount directory
    ensure_directory "$PROJECT_ROOT/mnt-rootfs" || {
        handle_error "Failed to create mount directory" "fatal"
        return 1
    }
    
    # Copy rootfs tarball
    log_message "INFO" "Copying rootfs tarball from $buildroot_path"
    cp "$buildroot_path/output/images/rootfs.tar" "$PROJECT_ROOT/" || {
        handle_error "Failed to copy rootfs tarball" "fatal"
        return 1
    }
    
    # Create rootfs image file
    create_rootfs_image "$buildroot_year" || {
        handle_error "Failed to create rootfs image" "fatal"
        cleanup_old_files "$buildroot_year"
        return 1
    }
    
    # Verify image file was created
    if [ ! -f "$PROJECT_ROOT/rootfs-$buildroot_year.img" ]; then
        handle_error "Rootfs image file was not created" "fatal"
        cleanup_old_files "$buildroot_year"
        return 1
    fi
    
    # Mount the image
    log_message "INFO" "Mounting rootfs image"
    sudo mount -o loop "$PROJECT_ROOT/rootfs-$buildroot_year.img" "$PROJECT_ROOT/mnt-rootfs/" || {
        handle_error "Failed to mount rootfs image" "fatal"
        cleanup_old_files "$buildroot_year"
        return 1
    }
    
    # Extract rootfs to mounted image
    log_message "INFO" "Extracting rootfs to mounted image"
    sudo tar -xvf "$PROJECT_ROOT/rootfs.tar" -C "$PROJECT_ROOT/mnt-rootfs/" > /dev/null || {
        handle_error "Failed to extract rootfs tarball" "fatal"
        # Try to unmount before returning
        sudo umount "$PROJECT_ROOT/mnt-rootfs/" 2>/dev/null
        cleanup_old_files "$buildroot_year"
        return 1
    }
    
    # Install kernel modules and firmware
    install_modules_and_firmware || {
        handle_error "Failed to install kernel modules and firmware" "fatal"
        # Try to unmount before returning
        sudo umount "$PROJECT_ROOT/mnt-rootfs/" 2>/dev/null
        cleanup_old_files "$buildroot_year"
        return 1
    }
    
    # Sync to ensure all writes complete
    sync
    
    # Prompt user to unmount
    log_message "INFO" "Rootfs image prepared. Press Enter to unmount and finalize..."
    read -p "Enter to unmount and clean folders : " yn
    
    # Clean up
    cleanup_after_build "$buildroot_year" || {
        handle_error "Failed to cleanup after build" "warning"
        return_code=1
    }
    
    if [ $return_code -eq 0 ]; then
        log_message "INFO" "Rootfs image generation completed successfully"
    else
        log_message "WARN" "Rootfs image generation completed with warnings"
    fi
    
    return $return_code
}

#-----------------------------------------------------------------------
# Mount Cleanup Function
#-----------------------------------------------------------------------

cleanup_mounts() {
    log_message "INFO" "Cleaning up existing mounts"
    local return_code=0
    
    # Check if the rootfs is currently mounted
    if mount | grep -q "$PROJECT_ROOT/mnt-rootfs"; then
        log_message "INFO" "Unmounting existing rootfs mount"
        sudo umount "$PROJECT_ROOT/mnt-rootfs/" || {
            log_message "WARN" "Failed to unmount existing rootfs, trying force unmount"
            sudo umount -f "$PROJECT_ROOT/mnt-rootfs/" || {
                handle_error "Failed to forcibly unmount existing rootfs" "warning"
                return_code=1
            }
        }
    fi
    
    # Remove mount directory if it exists
    if [ -d "$PROJECT_ROOT/mnt-rootfs" ]; then
        log_message "INFO" "Removing mnt-rootfs directory"
        sudo rm -rf "$PROJECT_ROOT/mnt-rootfs/" || {
            handle_error "Failed to remove mnt-rootfs directory" "warning"
            return_code=1
        }
    fi
    
    return $return_code
}

#-----------------------------------------------------------------------
# File Cleanup Function
#-----------------------------------------------------------------------

cleanup_old_files() {
    local buildroot_year="$1"
    local return_code=0
    
    # Validate inputs
    if [ -z "$buildroot_year" ]; then
        handle_error "Missing required buildroot_year parameter" "fatal"
        return 1
    fi
    
    log_message "INFO" "Cleaning up old files"
    
    # Remove old rootfs image if it exists
    if [ -f "$PROJECT_ROOT/rootfs-$buildroot_year.img" ]; then
        log_message "INFO" "Removing old rootfs image"
        sudo rm "$PROJECT_ROOT/rootfs-$buildroot_year.img" || {
            handle_error "Failed to remove old rootfs image" "warning"
            return_code=1
        }
    fi
    
    # Remove old rootfs tarball if it exists
    if [ -f "$PROJECT_ROOT/rootfs.tar" ]; then
        log_message "INFO" "Removing old rootfs tarball"
        sudo rm "$PROJECT_ROOT/rootfs.tar" || {
            handle_error "Failed to remove old rootfs tarball" "warning"
            return_code=1
        }
    fi
    
    return $return_code
}

#-----------------------------------------------------------------------
# Image Creation Function
#-----------------------------------------------------------------------

create_rootfs_image() {
    local buildroot_year="$1"
    
    # Validate inputs
    if [ -z "$buildroot_year" ]; then
        handle_error "Missing required buildroot_year parameter" "fatal"
        return 1
    fi
    
    # Verify ROOTFS_SIZE_MB is set and valid
    if [ -z "$ROOTFS_SIZE_MB" ] || ! [[ "$ROOTFS_SIZE_MB" =~ ^[0-9]+$ ]]; then
        handle_error "Invalid or missing ROOTFS_SIZE_MB configuration" "fatal"
        return 1
    fi
    
    log_message "INFO" "Creating rootfs image file ($ROOTFS_SIZE_MB MB)"
    
    if [ ! -f "$PROJECT_ROOT/rootfs-$buildroot_year.img" ]; then
        # Create empty image file
        dd if=/dev/zero of="$PROJECT_ROOT/rootfs-$buildroot_year.img" bs=1M count="$ROOTFS_SIZE_MB" || {
            handle_error "Failed to create empty rootfs image file" "fatal"
            return 1
        }
        
        # Format as ext4
        mkfs.ext4 -F -L "$ROOTFS_LABEL" "$PROJECT_ROOT/rootfs-$buildroot_year.img" || {
            handle_error "Failed to format rootfs image as ext4" "fatal"
            # Clean up the partial image
            rm -f "$PROJECT_ROOT/rootfs-$buildroot_year.img" 2>/dev/null
            return 1
        }
    else
        log_message "INFO" "Using existing rootfs image file"
    fi
    
    # Verify the image file exists after creation
    if [ ! -f "$PROJECT_ROOT/rootfs-$buildroot_year.img" ]; then
        handle_error "Failed to create rootfs image file" "fatal"
        return 1
    fi
    
    return 0
}

#-----------------------------------------------------------------------
# Kernel Modules Installation
#-----------------------------------------------------------------------

install_modules_and_firmware() {
    log_message "INFO" "Installing kernel modules and firmware"
    local return_code=0
    
    # Verify kernel directory exists
    if [ ! -d "$KERNEL_DIR" ]; then
        handle_error "Kernel directory not found at $KERNEL_DIR" "fatal"
        return 1
    fi
    
    # Install modules
    log_message "INFO" "Installing kernel modules"
    sudo make -C "$KERNEL_DIR" INSTALL_MOD_PATH="$PROJECT_ROOT/mnt-rootfs" modules_install || {
        handle_error "Failed to install kernel modules" "warning"
        return_code=1
    }
    
    # Install firmware if available
    if [ -d "$KERNEL_DIR/firmware" ]; then
        log_message "INFO" "Installing firmware files"
        sudo cp -r "$KERNEL_DIR/firmware/"* "$PROJECT_ROOT/mnt-rootfs/lib/firmware/" || {
            handle_error "Failed to install firmware files" "warning"
            return_code=1
        }
    fi
    
    return $return_code
}

#-----------------------------------------------------------------------
# Final Cleanup Function
#-----------------------------------------------------------------------

cleanup_after_build() {
    local buildroot_year="$1"
    local return_code=0
    
    # Validate inputs
    if [ -z "$buildroot_year" ]; then
        handle_error "Missing required buildroot_year parameter" "fatal"
        return 1
    fi
    
    log_message "INFO" "Cleaning up after build"
    
    # Unmount filesystem
    sudo umount "$PROJECT_ROOT/mnt-rootfs/" || {
        handle_error "Failed to unmount filesystem" "warning"
        return_code=1
    }
    
    # Remove mount directory
    if [ -d "$PROJECT_ROOT/mnt-rootfs/" ]; then
        sudo rm -rf "$PROJECT_ROOT/mnt-rootfs/" || {
            handle_error "Failed to remove mount directory" "warning"
            return_code=1
        }
    fi
    
    # Ensure Linux directory exists
    ensure_directory "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR" || {
        handle_error "Failed to create Linux directory" "warning"
        return_code=1
    }
    
    # Check if source image exists
    if [ ! -f "$PROJECT_ROOT/rootfs-$buildroot_year.img" ]; then
        handle_error "Source rootfs image file not found" "warning"
        return_code=1
    else
        # Move rootfs image to final location
        mv "$PROJECT_ROOT/rootfs-$buildroot_year.img" "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/rootfs.img" || {
            handle_error "Failed to move rootfs image to final location" "warning"
            return_code=1
        }
        
        # Highlight the final rootfs image
        highlight_output "ROOTFS" "Root Filesystem Image" "$PROJECT_ROOT/$ROCKCHIP_LINUX_DIR/rootfs.img" "Final rootfs image ready for flashing"
    fi
    
    # Remove tarball
    if [ -f "$PROJECT_ROOT/rootfs.tar" ]; then
        rm "$PROJECT_ROOT/rootfs.tar" || {
            handle_error "Failed to remove rootfs tarball" "warning"
            return_code=1
        }
    fi
    
    return $return_code
}

# Export functions
export -f rootfs_image_generate 