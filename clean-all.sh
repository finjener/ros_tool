#!/bin/bash

# ===============================================================
# Clean Tool
# ===============================================================
#
# DESCRIPTION:
#   Standalone tool for cleaning build artifacts from the workspace.
#   This script can clean kernel, buildroot, rootfs and flash artifacts
#   either selectively or all at once.
#
# USAGE:
#   ./clean-all.sh [OPTIONS]
#
# OPTIONS:
#   -k, --kernel        Clean kernel build artifacts
#   -b, --buildroot     Clean buildroot artifacts
#       --target=NAME   Clean specific target (radxa, rasp3)
#   -r, --rootfs        Clean rootfs artifacts
#   -f, --flash         Clean flash artifacts
#   -a, --all           Clean all artifacts
#   -d, --deep          Perform deep cleaning (remove downloads, sources)
#   -h, --help          Show this help
#
# EXAMPLES:
#   # Clean only kernel build artifacts:
#   ./clean-all.sh --kernel
#
#   # Clean buildroot artifacts for a specific target:
#   ./clean-all.sh --buildroot --target=radxa
#
#   # Clean everything (normal level):
#   ./clean-all.sh --all
#
#   # Deep clean everything (including sources and downloads):
#   ./clean-all.sh --all --deep
#
#   # Clean rootfs and flash artifacts only:
#   ./clean-all.sh --rootfs --flash
#
# RETURN VALUES:
#   0 - Success
#   1 - Error in parameters
#
# DEPENDENCIES:
#   - scripts/clean.sh (module containing cleaning functions)
#   - scripts/config.sh (configuration file)
#   - scripts/utils.sh (utility functions)
#
# ===============================================================

# Set error handling
set -o pipefail

# Get script directory and create absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/scripts/config.sh"
UTILS_PATH="${SCRIPT_DIR}/scripts/utils.sh"
CLEAN_PATH="${SCRIPT_DIR}/scripts/clean.sh"

# Check for required script files
check_required_files() {
    local missing=0
    
    if [ ! -f "$CONFIG_PATH" ]; then echo "ERROR: Config file missing: $CONFIG_PATH"; missing=1; fi
    if [ ! -f "$UTILS_PATH" ]; then echo "ERROR: Utils file missing: $UTILS_PATH"; missing=1; fi
    if [ ! -f "$CLEAN_PATH" ]; then echo "ERROR: Clean module missing: $CLEAN_PATH"; missing=1; fi
    
    if [ $missing -eq 1 ]; then
        echo "One or more required script files are missing."
        echo "Please ensure all script files are in the correct locations."
        exit 1
    fi
}

# Check required files before proceeding
check_required_files

# Source necessary files
source "$CONFIG_PATH" || { echo "ERROR: Failed to load configuration"; exit 1; }
source "$UTILS_PATH" || { echo "ERROR: Failed to load utilities"; exit 1; }
source "$CLEAN_PATH" || { echo "ERROR: Failed to load clean module"; exit 1; }

# Set log level based on environment variable if present
if [ -n "$ROS_TOOL_LOG_LEVEL" ]; then
    set_log_level "$ROS_TOOL_LOG_LEVEL"
    log_message "INFO" "Log level set to $ROS_TOOL_LOG_LEVEL"
else
    # Default to info level
    set_log_level "info"
fi

# Display help
show_help() {
    echo "Clean Tool - Remove build artifacts"
    echo ""
    echo "Usage: ./clean-all.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -k, --kernel        Clean kernel build artifacts"
    echo "  -b, --buildroot     Clean buildroot artifacts"
    echo "      --target=NAME   Clean specific target (radxa, rasp3)"
    echo "  -r, --rootfs        Clean rootfs artifacts"
    echo "  -f, --flash         Clean flash artifacts"
    echo "  -a, --all           Clean all artifacts"
    echo "  -d, --deep          Perform deep cleaning (remove downloads, sources)"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  ./clean-all.sh --kernel         # Clean only kernel artifacts"
    echo "  ./clean-all.sh --buildroot --target=radxa  # Clean radxa buildroot"
    echo "  ./clean-all.sh --all            # Clean everything (normal)"
    echo "  ./clean-all.sh --all --deep     # Clean everything deeply"
    echo ""
}

# Check if no arguments were provided
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

# Initialize flags
CLEAN_KERNEL=0
CLEAN_BUILDROOT=0
CLEAN_ROOTFS=0
CLEAN_FLASH=0
CLEAN_ALL=0
DEEP_CLEAN=0
TARGET=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        -k|--kernel)
            CLEAN_KERNEL=1
            shift
            ;;
        -b|--buildroot)
            CLEAN_BUILDROOT=1
            shift
            ;;
        --target=*)
            TARGET="${arg#*=}"
            shift
            ;;
        -r|--rootfs)
            CLEAN_ROOTFS=1
            shift
            ;;
        -f|--flash)
            CLEAN_FLASH=1
            shift
            ;;
        -a|--all)
            CLEAN_ALL=1
            shift
            ;;
        -d|--deep)
            DEEP_CLEAN=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_message "ERROR" "Unknown option: $arg"
            show_help
            exit 1
            ;;
    esac
done

# Validate target if specified
if [[ -n "$TARGET" && "$TARGET" != "radxa" && "$TARGET" != "rasp3" ]]; then
    log_message "ERROR" "Invalid target: $TARGET. Must be 'radxa' or 'rasp3'"
    exit 1
fi

# Check if we need a target but none was specified
if [[ $CLEAN_BUILDROOT -eq 1 && -z "$TARGET" ]]; then
    log_message "WARN" "No target specified for buildroot cleaning, will clean all targets"
fi

# Check for sudo requirements
if [[ $CLEAN_ROOTFS -eq 1 || $CLEAN_ALL -eq 1 ]]; then
    if ! sudo -n true 2>/dev/null; then
        log_message "WARN" "This operation requires sudo privileges to unmount filesystems."
        log_message "WARN" "You may be prompted for your password."
    fi
fi

# Check for root
if [ "$EUID" -eq 0 ]; then
    log_message "WARN" "This script should not be run as root"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_message "INFO" "Exiting as requested"
        exit 1
    fi
fi

# Perform cleaning based on flags
log_message "INFO" "Starting cleaning process"

if [ $CLEAN_ALL -eq 1 ]; then
    if [ $DEEP_CLEAN -eq 1 ]; then
        log_message "INFO" "Performing deep cleanup of all components"
        clean_all "deep" || handle_error "Deep cleaning failed" "fatal"
    else
        log_message "INFO" "Performing normal cleanup of all components"
        clean_all "normal" || handle_error "Normal cleaning failed" "fatal"
    fi
else
    # Individual component cleaning
    if [ $CLEAN_KERNEL -eq 1 ]; then
        log_message "INFO" "Cleaning kernel build artifacts"
        clean_kernel || handle_error "Kernel cleaning failed" "warning"
    fi
    
    if [ $CLEAN_BUILDROOT -eq 1 ]; then
        log_message "INFO" "Cleaning buildroot artifacts for target: $TARGET"
        clean_buildroot "$TARGET" || handle_error "Buildroot cleaning failed" "warning"
    fi
    
    if [ $CLEAN_ROOTFS -eq 1 ]; then
        log_message "INFO" "Cleaning rootfs artifacts"
        clean_rootfs || handle_error "Rootfs cleaning failed" "warning"
    fi
    
    if [ $CLEAN_FLASH -eq 1 ]; then
        log_message "INFO" "Cleaning flash artifacts"
        clean_flash || handle_error "Flash cleaning failed" "warning"
    fi
fi

log_message "INFO" "Cleaning operations completed successfully" 