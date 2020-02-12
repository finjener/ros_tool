#!/bin/bash

#########################################################################
# ROS Tool - Main Script
#########################################################################
# 
# This is the main entry point for the ROS Tool system, which handles
# building custom Linux distributions for embedded platforms.
#
# The script provides a command-line interface for:
# - Building custom kernels
# - Creating root filesystems  
# - Configuring Buildroot
# - Flashing devices
# - Cleaning build artifacts
#
# The system features enhanced output highlighting that clearly displays
# paths to generated files and artifacts with color-coded formatting.
#
#########################################################################

# DESCRIPTION:
#   A comprehensive build and configuration tool for embedded Linux systems.
#   This tool handles kernel compilation, buildroot setup, rootfs generation,
#   and device flashing for various hardware targets.
#
# USAGE:
#   ./run.sh [OPTIONS]
#
# OPTIONS:
#   --kernel, -k            Build the kernel
#   --target=NAME, -t NAME  Specify target hardware (radxa, rasp3)
#   --pack, -p              Generate rootfs image
#   --pack-radxa            Generate rootfs image for Radxa
#   --flash, -f             Flash the generated image
#   --clean [deep|only]     Clean build artifacts 
#                             deep: remove sources and downloaded files
#                             only: clean without building anything
#   --verbose, -v           Show full build output (all command output)
#   --quiet, -q             Show progress indicators with minimal output (default)
#   --help, -h              Show help information
#
# LEGACY MODE (backward compatibility):
#   ./run.sh -build-kernel rasp3 -pack 0
#   ./run.sh -build-kernel rasp3 -pack-radxa -flash
#
# EXAMPLES:
#   # Build kernel for raspberry pi 3 and generate rootfs:
#   ./run.sh --kernel --target=rasp3 --pack
#
#   # Clean workspace, then build kernel for radxa:
#   ./run.sh --clean --kernel --target=radxa
#
#   # Only clean the workspace deeply (remove sources):
#   ./run.sh --clean deep only
#
#   # Build kernel for radxa and flash the device:
#   ./run.sh --kernel --target=radxa --pack-radxa --flash
#
# RETURN VALUES:
#   0 - Success
#   1 - Error in parameters or execution
#
# DEPENDENCIES:
#   - Bash 4.0+
#   - Ubuntu 14.04+ (preferably 20.04 or newer)
#   - Required packages installed through tool's dependency installation
#
#########################################################################

#-----------------------------------------------------------------------
# Initial Settings
#-----------------------------------------------------------------------

# Enable error propagation in pipelines (e.g., cmd | tee) for proper error handling
set -o pipefail

#-----------------------------------------------------------------------
# Help & Information Functions
#-----------------------------------------------------------------------

# Display help information about the script
# This function prints usage, options, and examples
show_help() {
    echo "Run Tool - Version 2.0"
    echo "----------------------"
    echo "A comprehensive build and configuration tool for embedded Linux systems"
    echo ""
    echo "Usage: ./run.sh [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --kernel, -k            Build the kernel"
    echo "  --target=NAME, -t NAME  Specify target hardware (radxa, rasp3)"
    echo "  --pack, -p              Generate rootfs image"
    echo "  --pack-radxa            Generate rootfs image for Radxa"
    echo "  --flash, -f             Flash the generated image"
    echo "  --clean [deep|only]     Clean build artifacts (optional: deep clean, only clean without build)"
    echo "  --verbose, -v           Show full build output (all command output)"
    echo "  --quiet, -q             Show progress indicators with minimal output (default)"
    echo "  --help, -h              Show this help"
    echo ""
    echo "EXAMPLES:"
    echo "  ./run.sh --kernel --target=rasp3 --pack       # Build kernel for rasp3, generate rootfs"
    echo "  ./run.sh --kernel --target=radxa --pack-radxa # Build kernel for radxa, generate radxa rootfs"
    echo "  ./run.sh --clean deep --kernel --target=rasp3 # Deep clean before building kernel"
    echo "  ./run.sh --clean only                         # Only clean without building"
    echo "  ./run.sh --kernel --target=rasp3 --verbose    # Build kernel showing all output"
    echo ""
    echo "Legacy mode is supported for backward compatibility:"
    echo "  ./run.sh -build-kernel rasp3 -pack 0          # Traditional parameter style"
    echo ""
    echo "OUTPUT DISPLAY:"
    echo "  Build results and artifact paths are highlighted in the output with"
    echo "  color-coded formatting for easy identification. Look for boxed sections"
    echo "  that show file locations, sizes, and descriptions."
    echo ""
}

#-----------------------------------------------------------------------
# Setup & Environment Preparation
#-----------------------------------------------------------------------

# Check if the script is being run with bash (required)
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script requires bash. Please run it with bash."
    exit 1
fi

# Get absolute paths for script directory and dependent modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/scripts/config.sh"
UTILS_PATH="${SCRIPT_DIR}/scripts/utils.sh"
KERNEL_PATH="${SCRIPT_DIR}/scripts/kernel_build.sh"
BUILDROOT_PATH="${SCRIPT_DIR}/scripts/buildroot.sh"
ROOTFS_PATH="${SCRIPT_DIR}/scripts/rootfs.sh"
FLASH_PATH="${SCRIPT_DIR}/scripts/flash.sh"
CLEAN_PATH="${SCRIPT_DIR}/scripts/clean.sh"

# Display paths for debugging purposes
echo "Script directory: $SCRIPT_DIR"
echo "Config path: $CONFIG_PATH"
echo "Utils path: $UTILS_PATH"
echo "Kernel path: $KERNEL_PATH"
echo "Buildroot path: $BUILDROOT_PATH"
echo "Rootfs path: $ROOTFS_PATH"
echo "Flash path: $FLASH_PATH"
echo "Clean path: $CLEAN_PATH"

# Verify all required script files exist before proceeding
# This prevents cryptic errors if files are missing
check_required_files() {
    local missing=0
    
    if [ ! -f "$CONFIG_PATH" ]; then echo "Config file MISSING"; missing=1; else echo "Config file exists"; fi
    if [ ! -f "$UTILS_PATH" ]; then echo "Utils file MISSING"; missing=1; else echo "Utils file exists"; fi
    if [ ! -f "$KERNEL_PATH" ]; then echo "Kernel file MISSING"; missing=1; else echo "Kernel file exists"; fi
    if [ ! -f "$BUILDROOT_PATH" ]; then echo "Buildroot file MISSING"; missing=1; else echo "Buildroot file exists"; fi
    if [ ! -f "$ROOTFS_PATH" ]; then echo "Rootfs file MISSING"; missing=1; else echo "Rootfs file exists"; fi
    if [ ! -f "$FLASH_PATH" ]; then echo "Flash file MISSING"; missing=1; else echo "Flash file exists"; fi
    if [ ! -f "$CLEAN_PATH" ]; then echo "Clean file MISSING"; missing=1; else echo "Clean file exists"; fi
    
    if [ $missing -eq 1 ]; then
        echo "ERROR: One or more required script files are missing."
        echo "Please ensure all script files are in the correct locations."
        exit 1
    fi
}

# Verify all required files exist
check_required_files

# Load configuration and modules
echo "Loading configuration and modules..."

# Source utils first and only once
source "$UTILS_PATH" || {
    echo "ERROR: Failed to load utils module"
    exit 1
}

# Export the readonly variables so they're available to other scripts
export LOG_LEVEL_ERROR LOG_LEVEL_WARN LOG_LEVEL_INFO LOG_LEVEL_DEBUG
export COLOR_RED COLOR_YELLOW COLOR_GREEN COLOR_BLUE COLOR_RESET
export COLOR_BOLD COLOR_CYAN COLOR_PURPLE COLOR_UNDERLINE

# Now source other modules
source "$CONFIG_PATH" || {
    echo "ERROR: Failed to load config module"
    exit 1
}

source "$KERNEL_PATH" || {
    echo "ERROR: Failed to load kernel module"
    exit 1
}

source "$BUILDROOT_PATH" || {
    echo "ERROR: Failed to load buildroot module"
    exit 1
}

source "$ROOTFS_PATH" || {
    echo "ERROR: Failed to load rootfs module"
    exit 1
}

source "$FLASH_PATH" || {
    echo "ERROR: Failed to load flash module"
    exit 1
}

source "$CLEAN_PATH" || {
    echo "ERROR: Failed to load clean module"
    exit 1
}

# Configure log level - can be set via ROS_TOOL_LOG_LEVEL environment variable
if [ -n "$ROS_TOOL_LOG_LEVEL" ]; then
    set_log_level "$ROS_TOOL_LOG_LEVEL"
    log_message "INFO" "Log level set to $ROS_TOOL_LOG_LEVEL"
else
    # Default to info level
    set_log_level "info"
fi

#-----------------------------------------------------------------------
# Parameter Processing
#-----------------------------------------------------------------------

# Initialize default parameter values
BUILD_KERNEL=0        # Flag to build kernel
TARGET=""             # Target hardware (radxa, rasp3)
PACK_ROOTFS=0         # Flag to generate rootfs
PACK_RADXA=0          # Flag to generate Radxa-specific rootfs
FLASH=0               # Flag to flash device
CLEAN=0               # Flag to clean artifacts
CLEAN_LEVEL="normal"  # Clean level (normal or deep)
CLEAN_ONLY=0          # Flag to only clean without building
VERBOSE=0             # Output verbosity (0=quiet with progress, 1=verbose)
BUILD_LOGFILE="${SCRIPT_DIR}/build.log"  # Log file path

# Show help if no arguments provided
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

#-----------------------------------------------------------------------
# Command-Line Argument Parsing
#-----------------------------------------------------------------------

# Support two parameter styles:
# 1. Legacy style (-build-kernel target -pack [0|1] -flash [0|1])
# 2. Modern style (--option1 --option2=value)

# Check for legacy mode parameters
if [[ "$1" == "-build-kernel" ]]; then
    # Legacy parameter style detected
    log_message "INFO" "Legacy parameter style detected, using compatibility mode"
    BUILD_KERNEL=1
    
    if [ -z "$2" ]; then
        log_message "ERROR" "No target specified for kernel build"
        show_help
        exit 1
    fi
    
    TARGET="$2"
    
    # Validate target
    if [[ "$TARGET" != "radxa" && "$TARGET" != "rasp3" ]]; then
        log_message "ERROR" "Invalid target: $TARGET. Must be 'radxa' or 'rasp3'"
        exit 1
    fi
    
    # Parse packing option
    if [[ "$3" == "-pack" ]]; then
        PACK_ROOTFS=1
    elif [[ "$3" == "-pack-radxa" ]]; then
        PACK_RADXA=1
    elif [[ -n "$3" && "$3" != "0" ]]; then
        log_message "ERROR" "Unknown pack option: $3"
        show_help
        exit 1
    fi
    
    # Parse flashing option
    if [[ "$4" == "-flash" ]]; then
        FLASH=1
    elif [[ -n "$4" && "$4" != "0" ]]; then
        log_message "ERROR" "Unknown flash option: $4"
        show_help
        exit 1
    fi
else
    # Modern parameter style parsing
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # Build the kernel
            --kernel|-k)
                BUILD_KERNEL=1
                shift
                ;;
            # Target hardware specification (with equals sign)
            --target=*)
                TARGET="${1#*=}"  # Extract value after equals sign
                shift
                ;;
            # Target hardware specification (with space)
            -t)
                if [ -z "$2" ]; then
                    log_message "ERROR" "No value provided for --target/-t option"
                    show_help
                    exit 1
                fi
                TARGET="$2"
                shift 2
                ;;
            # Generate standard rootfs
            --pack|-p)
                PACK_ROOTFS=1
                shift
                ;;
            # Generate Radxa-specific rootfs
            --pack-radxa)
                PACK_RADXA=1
                shift
                ;;
            # Flash the device
            --flash|-f)
                FLASH=1
                shift
                ;;
            # Clean artifacts
            --clean)
                CLEAN=1
                # Check for deep clean option
                if [[ "$2" == "deep" ]]; then
                    CLEAN_LEVEL="deep"
                    shift
                fi
                # Check for clean-only option (no building)
                if [[ "$2" == "only" ]]; then
                    CLEAN_ONLY=1
                    shift
                fi
                shift
                ;;
            # Enable verbose output
            --verbose|-v)
                VERBOSE=1
                log_message "INFO" "Verbose mode enabled (showing all build output)"
                shift
                ;;
            # Enable quiet mode with progress display
            --quiet|-q)
                VERBOSE=0
                log_message "INFO" "Quiet mode enabled (hiding build output unless errors occur)"
                shift
                ;;
            # Show help information
            --help|-h)
                show_help
                exit 0
                ;;
            # Unknown option
            *)
                log_message "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
fi

#-----------------------------------------------------------------------
# Parameter Validation
#-----------------------------------------------------------------------

# Validate target hardware
if [[ "$TARGET" != "" && "$TARGET" != "radxa" && "$TARGET" != "rasp3" ]]; then
    log_message "ERROR" "Invalid target: $TARGET. Must be 'radxa' or 'rasp3'"
    exit 1
fi

# Require target when building kernel
if [[ $BUILD_KERNEL -eq 1 && -z "$TARGET" ]]; then
    log_message "ERROR" "Target must be specified when building kernel"
    show_help
    exit 1
fi

# Prevent specifying both rootfs types
if [[ $PACK_ROOTFS -eq 1 && $PACK_RADXA -eq 1 ]]; then
    log_message "ERROR" "Cannot specify both --pack and --pack-radxa"
    show_help
    exit 1
fi

# Require rootfs generation when flashing
if [[ $FLASH -eq 1 && $PACK_ROOTFS -eq 0 && $PACK_RADXA -eq 0 ]]; then
    log_message "ERROR" "Flash option requires either --pack or --pack-radxa"
    show_help
    exit 1
fi

#-----------------------------------------------------------------------
# Clean Handling
#-----------------------------------------------------------------------

# Perform cleaning if requested
if [ $CLEAN -eq 1 ]; then
    log_message "INFO" "Performing $CLEAN_LEVEL cleanup"
    clean_all "$CLEAN_LEVEL" || handle_error "Cleanup operation failed" "warning"
    
    # Exit if only cleaning was requested
    if [ $CLEAN_ONLY -eq 1 ]; then
        log_message "INFO" "Cleaning only, exiting"
        exit 0
    else
        log_message "INFO" "Continuing with build process after cleaning"
    fi
fi

#-----------------------------------------------------------------------
# System Setup
#-----------------------------------------------------------------------

# Detect system environment
CURRENT_PATH=$(pwd)
UBUNTU_VERSION=$(lsb_release -rs)
CONFIG_GUI=$(setup_gui_config)

# Add user to required groups for hardware access
# Only attempts to add if the group exists
if getent group vboxsf > /dev/null; then
    sudo adduser $USER vboxsf 2>/dev/null || log_message "WARN" "Failed to add user to vboxsf group"
fi

if getent group dialout > /dev/null; then
    sudo adduser $USER dialout 2>/dev/null || log_message "WARN" "Failed to add user to dialout group"
fi

#-----------------------------------------------------------------------
# Main Build Process
#-----------------------------------------------------------------------

# Main function - orchestrates the build process
run_tool() {
    log_message "INFO" "Starting Run Tool v2.0"
    
    # Build kernel if requested
    if [ $BUILD_KERNEL -eq 1 ]; then
        log_message "INFO" "Building kernel..."
        compile_kernel || handle_error "Kernel compilation failed" "fatal"
    fi
    
    # Visual separator for readability
    echo $'\n\n\n\n'
    
    # Handle Buildroot setup
    if [ -n "$TARGET" ]; then
        log_message "INFO" "Setting up Buildroot for $TARGET"
        setup_buildroot "$TARGET" || handle_error "Buildroot setup failed" "fatal"
    fi
    
    # Generate rootfs if requested (standard version)
    if [ $PACK_ROOTFS -eq 1 ]; then
        if [ -z "$TARGET" ]; then
            log_message "ERROR" "Target must be specified for rootfs generation"
            exit 1
        fi
        
        local buildroot_path="../$TARGET/${BUILDROOT_VERSIONS[0]}"
        
        if [ ! -d "$buildroot_path" ]; then
            log_message "ERROR" "Buildroot path not found: $buildroot_path"
            log_message "ERROR" "Did you run with --target=$TARGET first?"
            exit 1
        fi
        
        log_message "INFO" "Generating rootfs using Buildroot"
        rootfs_image_generate "${BUILDROOT_VERSIONS[1]}" "$buildroot_path" || handle_error "Rootfs generation failed" "fatal"
    fi
    
    # Handle Radxa specific packaging
    if [ $PACK_RADXA -eq 1 ]; then
        local buildroot_path="../radxa/${BUILDROOT_VERSIONS[0]}"
        
        if [ ! -d "$buildroot_path" ]; then
            log_message "ERROR" "Buildroot path not found: $buildroot_path"
            log_message "ERROR" "Did you run with --target=radxa first?"
            exit 1
        fi
        
        log_message "INFO" "Generating rootfs specifically for Radxa"
        rootfs_image_generate "${BUILDROOT_VERSIONS[1]}" "$buildroot_path" || handle_error "Radxa rootfs generation failed" "fatal"
        
        # Flash if requested
        if [ $FLASH -eq 1 ]; then
            log_message "INFO" "Flashing device..."
            package_and_flash "-flash" || handle_error "Device flashing failed" "fatal"
        else
            log_message "INFO" "Packaging without flashing..."
            package_and_flash "" || handle_error "Packaging failed" "fatal"
        fi
    fi
    
    log_message "INFO" "Run Tool execution completed successfully"
    return 0
}

#-----------------------------------------------------------------------
# Execution Safety Checks
#-----------------------------------------------------------------------

# Warn if running as root (not recommended for safety)
if [ "$EUID" -eq 0 ]; then
    log_message "WARN" "This script should not be run as root"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_message "INFO" "Exiting as requested"
        exit 1
    fi
fi

#-----------------------------------------------------------------------
# Run Process
#-----------------------------------------------------------------------

# Install dependencies before running
log_message "INFO" "Checking and installing dependencies..."
install_dependencies || handle_error "Failed to install dependencies" "warning"

# Execute the main build process
run_tool
exit_code=$?

# Print final status message
if [ $exit_code -eq 0 ]; then
    log_message "INFO" "Run Tool completed successfully"
else
    log_message "ERROR" "Run Tool encountered errors (Exit code: $exit_code)"
fi

exit $exit_code

