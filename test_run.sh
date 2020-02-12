#!/bin/bash

# ===============================================================
# Test Run.sh - Testing Mode
# ===============================================================
#
# DESCRIPTION:
#   Testing version of run.sh that skips all actual build processes
#   but provides realistic mock behavior and detailed logging of what
#   would happen in a real execution.
#
# USAGE:
#   ./test_run.sh [OPTIONS]
#   
#   Same options as run.sh, but nothing is actually built or flashed.
#
# ENVIRONMENT VARIABLES:
#   TEST_FAIL_STAGE - Set to a stage name to simulate failure at that stage:
#     - "kernel"    - Simulate kernel compilation failure
#     - "buildroot" - Simulate buildroot setup failure
#     - "rootfs"    - Simulate rootfs image generation failure
#     - "flash"     - Simulate flashing failure
#
#   TEST_LOG_LEVEL - Set log level (error, warn, info, debug)
#
# ===============================================================

# Get script directory and set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/scripts/config.sh"
UTILS_PATH="${SCRIPT_DIR}/scripts/utils.sh"

# Print colorized banner
echo -e "\033[1;36m==================================\033[0m"
echo -e "\033[1;33m          TESTING MODE           \033[0m"
echo -e "\033[1;36m==================================\033[0m"
echo -e "\033[1;37mNo actual builds will be performed\033[0m"
echo -e "\033[1;36m==================================\033[0m"

# Import test configuration
TEST_LOG_LEVEL=${TEST_LOG_LEVEL:-"info"}
TEST_FAIL_STAGE=${TEST_FAIL_STAGE:-"none"}

# Source only config and utils
echo "Loading configuration files..."
source "$CONFIG_PATH" || { echo "Failed to load config"; exit 1; }
source "$UTILS_PATH" || { echo "Failed to load utils"; exit 1; }

# Set log level for testing
set_log_level "$TEST_LOG_LEVEL"
log_message "INFO" "Test mode initialized with log level: $TEST_LOG_LEVEL"

if [ "$TEST_FAIL_STAGE" != "none" ]; then
    log_message "WARN" "Test configured to fail at stage: $TEST_FAIL_STAGE"
fi

# Mock functions to replace actual implementations
# ------------------------------------------------

simulate_command_output() {
    local command=$1
    local duration=${2:-1}  # Default duration of 1 second
    
    log_message "DEBUG" "Simulating command: $command"
    # Print progress dots to simulate work
    echo -n "Running $command "
    for i in $(seq 1 $duration); do
        echo -n "."
        sleep 0.1
    done
    echo " done"
}

simulate_failure() {
    local stage=$1
    if [ "$TEST_FAIL_STAGE" == "$stage" ]; then
        log_message "ERROR" "Simulating failure in $stage stage"
        return 1
    fi
    return 0
}

compile_kernel() {
    log_message "MOCK" "=== KERNEL COMPILATION ==="
    log_message "MOCK" "Would prepare kernel build environment"
    simulate_command_output "configure kernel" 3
    
    log_message "MOCK" "Would compile kernel with make -j2 ARCH=arm"
    simulate_command_output "make kernel.img" 5
    
    log_message "MOCK" "Would install kernel modules"
    simulate_command_output "make modules_install" 3
    
    log_message "MOCK" "Would create boot image"
    simulate_command_output "mkbootimg" 2
    
    # Simulate failure if configured
    simulate_failure "kernel"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_message "MOCK" "Kernel compilation would complete successfully"
    else
        log_message "ERROR" "Kernel compilation would fail"
    fi
    
    return $result
}

setup_buildroot() {
    local target="$1"
    
    # Validate target
    if [[ "$target" != "radxa" && "$target" != "rasp3" ]]; then
        log_message "ERROR" "MOCK: Invalid target: $target (must be radxa or rasp3)"
        return 1
    fi
    
    log_message "MOCK" "=== BUILDROOT SETUP FOR $target ==="
    log_message "MOCK" "Would download and extract Buildroot for $target"
    simulate_command_output "wget and extract buildroot" 4
    
    log_message "MOCK" "Would configure Buildroot with GUI tool"
    simulate_command_output "make xconfig" 2
    
    log_message "MOCK" "Would build Buildroot (this would take a long time in reality)"
    simulate_command_output "make" 6
    
    # Simulate failure if configured
    simulate_failure "buildroot"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_message "MOCK" "Buildroot setup would complete successfully"
    else
        log_message "ERROR" "Buildroot setup would fail"
    fi
    
    return $result
}

rootfs_image_generate() {
    local year="$1"
    local path="$2"
    
    # Validate inputs
    if [ -z "$year" ] || [ -z "$path" ]; then
        log_message "ERROR" "MOCK: Missing required parameters for rootfs_image_generate"
        return 1
    fi
    
    log_message "MOCK" "=== ROOTFS GENERATION ==="
    log_message "MOCK" "Would generate rootfs from: $path (year: $year)"
    
    log_message "MOCK" "Would clean up old mounts and files"
    simulate_command_output "cleanup old files" 2
    
    log_message "MOCK" "Would create rootfs image file ($ROOTFS_SIZE_MB MB)"
    simulate_command_output "dd if=/dev/zero" 3
    
    log_message "MOCK" "Would format rootfs image as ext4"
    simulate_command_output "mkfs.ext4" 2
    
    log_message "MOCK" "Would mount rootfs image"
    simulate_command_output "mount -o loop" 1
    
    log_message "MOCK" "Would extract rootfs files"
    simulate_command_output "tar -xvf" 4
    
    log_message "MOCK" "Would install kernel modules and firmware"
    simulate_command_output "copy modules" 3
    
    log_message "MOCK" "Would unmount and finalize rootfs"
    simulate_command_output "umount" 1
    
    # Simulate failure if configured
    simulate_failure "rootfs"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_message "MOCK" "Rootfs image generation would complete successfully"
    else
        log_message "ERROR" "Rootfs image generation would fail"
    fi
    
    return $result
}

package_and_flash() {
    local should_flash="$1"
    
    log_message "MOCK" "=== PACKAGING/FLASHING ==="
    log_message "MOCK" "Would create update.img from boot and rootfs images"
    simulate_command_output "mkupdate.sh" 3
    
    if [ "$should_flash" == "-flash" ]; then
        log_message "MOCK" "Would flash device with update.img"
        log_message "MOCK" "Would prompt user to put device in maskrom mode"
        log_message "MOCK" "Would run: sudo ./upgrade_tool uf update.img"
        simulate_command_output "flashing device" 5
        
        # Simulate failure if configured
        simulate_failure "flash"
        local result=$?
        
        if [ $result -eq 0 ]; then
            log_message "MOCK" "Device flashing would complete successfully"
        else
            log_message "ERROR" "Device flashing would fail"
        fi
        
        return $result
    else
        log_message "MOCK" "Packaging completed (no flashing requested)"
        return 0
    fi
}

# Override system commands with mock versions
# -------------------------------------------
make() { 
    log_message "MOCK" "Would run: make $*"
    return 0
}

git() { 
    log_message "MOCK" "Would run: git $*"
    return 0
}

sudo() { 
    log_message "MOCK" "Would run with sudo: $*"
    return 0
}

zenity() { 
    local result=""
    
    # For questions, return "yes"
    if [[ "$1" == "--question" ]]; then 
        log_message "MOCK" "Would show zenity question: ${*:2}"
        log_message "MOCK" "User would select: Yes"
        return 0
    fi
    
    # For compiler selection
    if [[ "$*" == *"Compiler"* ]]; then 
        result="arm-eabi-4.6"
        log_message "MOCK" "User would select compiler: $result"
    fi
    
    # For buildroot selection
    if [[ "$*" == *"buildroot"* ]]; then 
        result="${BUILDROOT_VERSIONS[0]}"
        log_message "MOCK" "User would select buildroot version: $result"
    fi
    
    echo "$result"
    return 0
}

# Catch any other commands that might be executed
function command_not_found_handle() {
    log_message "MOCK" "Would run: $*"
    return 0
}

# Export all mock functions
export -f compile_kernel setup_buildroot rootfs_image_generate package_and_flash
export -f make git sudo zenity command_not_found_handle
export -f simulate_command_output simulate_failure

# Improved run_tool function that supports both legacy and modern parameter styles
run_tool() {
    log_message "MOCK" "=== STARTING RUN TOOL (TEST MODE) ==="
    local build_kernel=0
    local target=""
    local pack_rootfs=0
    local pack_radxa=0
    local flash=0
    local clean=0
    local clean_level="normal"
    local clean_only=0
    local return_code=0
    
    # Legacy mode detection
    if [[ "$1" == "-build-kernel" ]]; then
        # Legacy parameter style detected
        log_message "INFO" "Legacy parameter style detected"
        build_kernel=1
        target="$2"
        
        if [[ "$3" == "-pack" ]]; then
            pack_rootfs=1
        elif [[ "$3" == "-pack-radxa" ]]; then
            pack_radxa=1
        fi
        
        if [[ "$4" == "-flash" ]]; then
            flash=1
        fi
    else
        # Modern parameter parsing - simplified for testing
        for arg in "$@"; do
            case "$arg" in
                --kernel|-k)
                    build_kernel=1
                    ;;
                --target=*)
                    target="${arg#*=}"
                    ;;
                -t)
                    # Skip next argument
                    target="$2"
                    shift
                    ;;
                --pack|-p)
                    pack_rootfs=1
                    ;;
                --pack-radxa)
                    pack_radxa=1
                    ;;
                --flash|-f)
                    flash=1
                    ;;
                --clean)
                    clean=1
                    # Check for deep clean
                    if [[ "$2" == "deep" ]]; then
                        clean_level="deep"
                        shift
                    fi
                    # Check for clean only
                    if [[ "$2" == "only" ]]; then
                        clean_only=1
                        shift
                    fi
                    ;;
                --help|-h)
                    # Already handled in main
                    ;;
                *)
                    # Skip unknown arguments
                    ;;
            esac
            shift
        done
    fi
    
    # Validate parameters
    if [[ -n "$target" && "$target" != "radxa" && "$target" != "rasp3" ]]; then
        log_message "ERROR" "Invalid target: $target. Must be 'radxa' or 'rasp3'"
        return 1
    fi
    
    if [[ $build_kernel -eq 1 && -z "$target" ]]; then
        log_message "ERROR" "Target must be specified when building kernel"
        return 1
    fi
    
    # Handle cleaning if requested
    if [ $clean -eq 1 ]; then
        log_message "MOCK" "Would clean workspace (level: $clean_level)"
        simulate_command_output "cleaning workspace" 3
        
        if [ $clean_only -eq 1 ]; then
            log_message "MOCK" "Cleaning only, would exit"
            return 0
        fi
    fi
    
    # Build kernel if requested
    if [ $build_kernel -eq 1 ]; then
        log_message "MOCK" "Would build kernel for target: $target"
        compile_kernel || {
            log_message "ERROR" "Kernel compilation would fail"
            return_code=1
        }
    fi
    
    # Handle Buildroot setup
    if [ -n "$target" ]; then
        log_message "MOCK" "Would set up Buildroot for target: $target"
        setup_buildroot "$target" || {
            log_message "ERROR" "Buildroot setup would fail"
            return_code=1
        }
    fi
    
    # Generate rootfs if requested
    if [ $pack_rootfs -eq 1 ]; then
        if [ -z "$target" ]; then
            log_message "ERROR" "Target must be specified for rootfs generation"
            return 1
        fi
        
        local buildroot_path="../$target/${BUILDROOT_VERSIONS[0]}"
        log_message "MOCK" "Would generate rootfs with Buildroot from: $buildroot_path"
        rootfs_image_generate "${BUILDROOT_VERSIONS[1]}" "$buildroot_path" || {
            log_message "ERROR" "Rootfs generation would fail"
            return_code=1
        }
    fi
    
    # Handle Radxa specific packaging
    if [ $pack_radxa -eq 1 ]; then
        local buildroot_path="../radxa/${BUILDROOT_VERSIONS[0]}"
        log_message "MOCK" "Would generate rootfs with Buildroot from: $buildroot_path (radxa specific)"
        rootfs_image_generate "${BUILDROOT_VERSIONS[1]}" "$buildroot_path" || {
            log_message "ERROR" "Radxa rootfs generation would fail"
            return_code=1
        }
        
        # Flash if requested
        if [ $flash -eq 1 ]; then
            log_message "MOCK" "Would flash device"
            package_and_flash "-flash" || {
                log_message "ERROR" "Device flashing would fail"
                return_code=1
            }
        else
            log_message "MOCK" "Would package without flashing"
            package_and_flash "" || {
                log_message "ERROR" "Packaging would fail"
                return_code=1
            }
        fi
    fi
    
    if [ $return_code -eq 0 ]; then
        log_message "MOCK" "Run Tool (TEST MODE) completed successfully"
    else
        log_message "ERROR" "Run Tool (TEST MODE) completed with errors"
    fi
    
    return $return_code
}

# Print all parameters for debugging
log_message "INFO" "Command line arguments: $*"

# Mock dependency installation
log_message "MOCK" "Dependency installation would be skipped"

# Help function to support the same options as run.sh
show_help() {
    echo "Test Run Tool - Test Mode"
    echo "----------------------"
    echo "A testing version of run.sh that simulates execution without making actual changes"
    echo ""
    echo "Usage: ./test_run.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --kernel, -k            Test kernel build process"
    echo "  --target=NAME, -t NAME  Specify target hardware (radxa, rasp3)"
    echo "  --pack, -p              Test rootfs generation process"
    echo "  --pack-radxa            Test radxa-specific rootfs generation"
    echo "  --flash, -f             Test device flashing process"
    echo "  --clean [deep|only]     Test cleaning process"
    echo "  --help, -h              Show this help"
    echo ""
    echo "Environment variables for testing:"
    echo "  TEST_FAIL_STAGE         Set to simulate failure at a specific stage"
    echo "                          (kernel, buildroot, rootfs, flash)"
    echo "  TEST_LOG_LEVEL          Set log level (error, warn, info, debug)"
    echo ""
    echo "Examples:"
    echo "  # Basic kernel build test for Radxa:"
    echo "  ./test_run.sh --kernel --target=radxa"
    echo ""
    echo "  # Full build and flash test:"
    echo "  ./test_run.sh --kernel --target=radxa --pack-radxa --flash"
    echo ""
    echo "  # Test with simulated kernel compilation failure:"
    echo "  TEST_FAIL_STAGE=kernel ./test_run.sh --kernel --target=radxa"
    echo ""
    echo "  # Test with detailed debug logging:"
    echo "  TEST_LOG_LEVEL=debug ./test_run.sh --kernel --target=radxa --pack"
    echo ""
    echo "  # Test cleaning process (deep clean):"
    echo "  ./test_run.sh --clean deep"
    echo ""
    echo "  # Test with legacy parameter style:"
    echo "  ./test_run.sh -build-kernel radxa -pack-radxa -flash"
    echo ""
    echo "  # Test multiple operations with a failure at flashing stage:"
    echo "  TEST_FAIL_STAGE=flash ./test_run.sh --clean --kernel --target=radxa --pack-radxa --flash"
    echo ""
}

# Check if help is requested
if [[ "$1" == "--help" || "$1" == "-h" || $# -eq 0 ]]; then
    show_help
    exit 0
fi

# Run the tool with the arguments
run_tool "$@"
exit_code=$?

# Report final status
if [ $exit_code -eq 0 ]; then
    log_message "INFO" "Test completed successfully - all operations would succeed"
else
    log_message "ERROR" "Test completed with errors - some operations would fail"
fi

exit $exit_code 