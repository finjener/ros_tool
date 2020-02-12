#!/bin/bash

#########################################################################
# Utility Functions Module
#########################################################################
# 
# This file contains shared utility functions used across the ROS Tool.
# It provides logging, error handling, command execution, and system
# management functionality that's reused by other modules.
#
# Functions are organized into categories:
# - Configuration & Environment
# - Logging & Error Handling
# - Command Execution
# - System Operations
# - UI & Progress Display
#
#########################################################################

#-----------------------------------------------------------------------
# Configuration & Environment
#-----------------------------------------------------------------------

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"

# Detect system information
UBUNTU_VERSION=$(lsb_release -rs)
CURRENT_PATH=$(pwd)

#-----------------------------------------------------------------------
# Logging & Error Handling
#-----------------------------------------------------------------------

# Log levels - ordered from most critical to most verbose
if [[ -z "${LOG_LEVEL_ERROR+x}" ]]; then
    readonly LOG_LEVEL_ERROR=0
    readonly LOG_LEVEL_WARN=1
    readonly LOG_LEVEL_INFO=2
    readonly LOG_LEVEL_DEBUG=3

    # Colors for output
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_BOLD='\033[1m'
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_PURPLE='\033[0;35m'
    readonly COLOR_UNDERLINE='\033[4m'
fi

# Default log level
LOG_LEVEL=$LOG_LEVEL_INFO

# Set the logging level for the system
# Parameters:
#   $1 - Log level (error, warn, info, debug)
set_log_level() {
    case "$1" in
        "error") LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        "warn")  LOG_LEVEL=$LOG_LEVEL_WARN ;;
        "info")  LOG_LEVEL=$LOG_LEVEL_INFO ;;
        "debug") LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        *) 
            echo "Invalid log level: $1. Using default (info)."
            LOG_LEVEL=$LOG_LEVEL_INFO ;;
    esac
    export LOG_LEVEL
}

# Enhanced log message function with colors and filtering by level
# Parameters:
#   $1 - Log level (ERROR, WARN, INFO, DEBUG, MOCK)
#   $2 - Message text to display
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    local level_name=""
    local level_value=0
    
    # Determine level settings and color
    case "$level" in
        "ERROR") 
            color="$COLOR_RED"
            level_name="ERROR"
            level_value=$LOG_LEVEL_ERROR
            ;;
        "WARN") 
            color="$COLOR_YELLOW"
            level_name="WARN "
            level_value=$LOG_LEVEL_WARN
            ;;
        "INFO") 
            color="$COLOR_GREEN"
            level_name="INFO "
            level_value=$LOG_LEVEL_INFO
            ;;
        "DEBUG") 
            color="$COLOR_BLUE"
            level_name="DEBUG"
            level_value=$LOG_LEVEL_DEBUG
            ;;
        "MOCK")
            color="$COLOR_BLUE"
            level_name="MOCK "
            level_value=$LOG_LEVEL_DEBUG
            ;;
        *) 
            color="$COLOR_GREEN"
            level_name="INFO "
            level_value=$LOG_LEVEL_INFO
            ;;
    esac
    
    # Only output if current log level permits
    if [ $level_value -le $LOG_LEVEL ]; then
        echo -e "${color}[$timestamp] [$level_name]${COLOR_RESET} $message"
    fi
}

# Standardized error handling with customizable behavior
# Parameters:
#   $1 - Error message
#   $2 - Error type (fatal, warning, continue)
#   $3 - Optional custom command to execute on error
handle_error() {
    local exit_code=$?
    local error_message="$1"
    local error_type="$2"  # fatal, warning, or continue
    local custom_action="$3"  # Optional custom command to execute
    
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR" "$error_message (Exit code: $exit_code)"
        
        # Execute custom action if provided
        if [ -n "$custom_action" ]; then
            eval "$custom_action"
        fi
        
        # Handle based on error type
        case "$error_type" in
            "fatal")
                log_message "ERROR" "Fatal error encountered. Exiting."
                exit $exit_code
                ;;
            "warning")
                log_message "WARN" "Warning: Operation failed but continuing execution."
                return $exit_code
                ;;
            "continue")
                log_message "INFO" "Non-critical error. Continuing execution."
                return 0
                ;;
            *)
                log_message "ERROR" "Unknown error type: $error_type. Treating as fatal."
                exit $exit_code
                ;;
        esac
    fi
    return 0
}

# Check if a required command is available
# Parameters:
#   $1 - Command to check
#   $2 - Optional package name that provides the command
#   $3 - Error type if command not found (default: warning)
check_command() {
    local cmd="$1"
    local package="$2"
    local error_type="${3:-warning}"
    
    if ! command -v "$cmd" &> /dev/null; then
        if [ -n "$package" ]; then
            handle_error "Command '$cmd' not found. Try installing package '$package'." "$error_type"
        else
            handle_error "Command '$cmd' not found." "$error_type"
        fi
        return 1
    fi
    return 0
}

# Check if a required file exists
# Parameters:
#   $1 - File path to check
#   $2 - Optional error message (default: "Required file not found")
#   $3 - Error type if file not found (default: warning)
check_file() {
    local file="$1"
    local message="${2:-Required file not found}"
    local error_type="${3:-warning}"
    
    if [ ! -f "$file" ]; then
        handle_error "$message: $file" "$error_type"
        return 1
    fi
    return 0
}

# Check if a required directory exists
# Parameters:
#   $1 - Directory path to check
#   $2 - Optional error message (default: "Required directory not found")
#   $3 - Error type if directory not found (default: warning)
check_directory() {
    local directory="$1"
    local message="${2:-Required directory not found}"
    local error_type="${3:-warning}"
    
    if [ ! -d "$directory" ]; then
        handle_error "$message: $directory" "$error_type"
        return 1
    fi
    return 0
}

#-----------------------------------------------------------------------
# Package & Dependency Management
#-----------------------------------------------------------------------

# Install a package if it's not already installed
# Parameters:
#   $1 - Package name to install
install_package() {
    if [ $(dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
        log_message "INFO" "Installing package: $1"
        sudo apt-get install -y $1 || handle_error "Failed to install package: $1" "warning"
    else
        log_message "DEBUG" "Package already installed: $1"
    fi
}

# Install all required dependencies defined in config.sh
# Returns: 0 on success, non-zero on failure
install_dependencies() {
    log_message "INFO" "Installing dependencies..."
    
    # Check for sudo access
    if ! sudo -n true 2>/dev/null; then
        log_message "WARN" "This script requires sudo privileges to install packages."
        log_message "WARN" "You may be prompted for your password."
    fi
    
    # Install common packages
    for package in "${COMMON_PACKAGES[@]}"; do
        install_package "$package"
    done

    # Install version-specific packages based on Ubuntu version
    if [[ "$UBUNTU_VERSION" == "16.04" || "$UBUNTU_VERSION" == "14.04" ]]; then
        for package in "${UBUNTU14_PACKAGES[@]}"; do
            install_package "$package"
        done
        
        # Check for mkbootimg and install from source if needed
        if check_command mkbootimg "" "continue"; then
            log_message "INFO" "mkbootimg exists"
        else
            log_message "INFO" "mkbootimg does not exist, building from source"
            
            # Ensure git is installed
            check_command git "git" "warning" || return 1
            
            cd "$PROJECT_ROOT/$ROCKCHIP_TOOLS_DIR" || handle_error "Cannot change to rockchip-tools directory" "fatal"
            git clone https://github.com/neo-technologies/rockchip-mkbootimg.git || handle_error "Failed to clone mkbootimg repository" "warning"
            cd rockchip-mkbootimg || handle_error "Cannot change to rockchip-mkbootimg directory" "fatal"
            make || handle_error "Failed to build mkbootimg" "warning"
            sudo make install || handle_error "Failed to install mkbootimg" "warning"
            cd "$CURRENT_PATH" || handle_error "Cannot change back to current directory" "warning"
        fi
    elif [[ "$UBUNTU_VERSION" == "20.04" || "$UBUNTU_VERSION" == "22.04" ]]; then
        for package in "${UBUNTU20_PACKAGES[@]}"; do
            install_package "$package"
        done
        
        # Install repo tool for Ubuntu 20.04/22.04
        install_repo_tool
    else
        log_message "WARN" "Unsupported Ubuntu version: $UBUNTU_VERSION. Some features may not work correctly."
    fi
    
    log_message "INFO" "Dependencies installation completed"
}

# Install Google's repo tool if not already installed
# Returns: 0 on success, non-zero on failure
install_repo_tool() {
    log_message "INFO" "Checking if repo tool is installed"
    
    if ! check_command repo "" "continue"; then
        log_message "INFO" "Installing Google's repo tool"
        
        # Create bin directory if it doesn't exist
        mkdir -p ~/.bin || handle_error "Failed to create ~/.bin directory" "warning"
        
        # Add to PATH if not already included
        if [[ ":$PATH:" != *":$HOME/.bin:"* ]]; then
            log_message "INFO" "Adding ~/.bin to PATH"
            export PATH="${HOME}/.bin:${PATH}"
            
            # Add to .bashrc for persistence if not already there
            if ! grep -q "PATH=\"\${HOME}/.bin:\${PATH}\"" ~/.bashrc; then
                echo 'export PATH="${HOME}/.bin:${PATH}"' >> ~/.bashrc || handle_error "Failed to update .bashrc" "warning"
                log_message "INFO" "Added PATH update to ~/.bashrc"
            fi
        fi
        
        # Download repo tool
        log_message "INFO" "Downloading repo tool"
        curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo || handle_error "Failed to download repo tool" "warning"
        
        # Make executable
        chmod a+rx ~/.bin/repo || handle_error "Failed to make repo executable" "warning"
        
        # Verify installation
        if check_command repo "" "continue"; then
        log_message "INFO" "repo tool installed successfully"
        else
            handle_error "repo tool installation failed" "warning"
        fi
    else
        log_message "DEBUG" "repo tool is already installed"
    fi
}

#-----------------------------------------------------------------------
# System Operations
#-----------------------------------------------------------------------

# Kill a process by name
# Parameters:
#   $1 - Process name pattern to kill
kill_process() {
    proc_name=$1
    if ! ps -fe | grep -q "$proc_name"; then
        log_message "DEBUG" "No process matching '$proc_name' found to kill"
        return 0
    fi
    
    # This complex awk command extracts the process ID and kills it with SIGKILL (9)
    ps -fe | awk 'NR==1{for (i=1; i<=NF; i++) {if ($i=="COMMAND") Ncmd=i; else if ($i=="PID") Npid=i} if (!Ncmd || !Npid) {print "wrong or no header" > "/dev/stderr"; exit} }$Ncmd~"/"name"$"{print "killing "$Ncmd" with PID " $Npid; system("kill -9 "$Npid)}' name=.*$proc_name.* || handle_error "Failed to kill process: $proc_name" "warning"
}

# Execute a binary in a safe manner
# Parameters:
#   $1 - Executable name to run (from /opt directory)
# Returns: PID of started process or 1 on failure
run_exec() {
    exec_name=$1
    
    if [ ! -f "/opt/$exec_name" ]; then
        handle_error "Binary not found: /opt/$exec_name" "warning"
        return 1
    fi
    
    cd /opt || handle_error "Cannot change to /opt directory" "fatal"
    
    chmod +x *.sh || handle_error "Failed to make scripts executable" "warning"
    chmod +x $exec_name || handle_error "Failed to make $exec_name executable" "warning"
    
    ./$exec_name &
    
    # Store PID
    local pid=$!
    log_message "INFO" "Started $exec_name with PID: $pid"
    
    # Check if process is running
    if ! ps -p $pid > /dev/null; then
        handle_error "Failed to start $exec_name" "warning"
        return 1
    fi
    
    return 0
}

# Scan Local Area Network for IP addresses
# Returns: List of discovered IP addresses
scan_lan() {
    # Check for required tools
    check_command arp-scan "arp-scan" "warning" || return 1
    check_command nm-tool "network-manager" "warning" || return 1
    
    IPs=$(sudo arp-scan --localnet --numeric --quiet --ignoredups | grep -E '([a-f0-9]{2}:){5}[a-f0-9]{2}' | awk '{print $1}') || handle_error "Failed to scan LAN" "warning"
    echo $IPs

    myIpAddr=$(sudo nm-tool | grep -i 'address' | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sed -n "$myip"p) || handle_error "Failed to get IP address" "warning"
    echo $myIpAddr
}

# Ensure a directory exists, creating it if necessary
# Parameters:
#   $1 - Path to directory that should exist
ensure_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1" || handle_error "Failed to create directory: $1" "warning"
        log_message "INFO" "Created directory: $1"
    fi
}

# Set up GUI configuration tool based on Ubuntu version
# Returns: Name of appropriate configuration tool (xconfig or gconfig)
setup_gui_config() {
    if [ "$UBUNTU_VERSION" == "16.04" ] || [ "$UBUNTU_VERSION" == "14.04" ]; then
        echo "xconfig"
    elif [ "$UBUNTU_VERSION" == "20.04" ]; then
        echo "gconfig"
    else
        echo "gconfig"
    fi
}

#-----------------------------------------------------------------------
# Command Execution & Progress Display
#-----------------------------------------------------------------------

# Execute a command with controlled verbosity and progress display
# Parameters:
#   $1 - Command to execute
#   $2 - Description of the command (for logging)
# Environment:
#   VERBOSE - Set to 1 for full output, 0 for progress indicator only
#   BUILD_LOGFILE - Path to log file (defaults to /tmp/build.log)
# Returns: Exit code of the executed command
execute_command() {
    local cmd="$1"
    local desc="$2"
    local logfile="${BUILD_LOGFILE:-/tmp/build.log}"
    local progress_file="/tmp/progress_$$_$RANDOM.log"
    
    log_message "INFO" "Starting: $desc"
    
    # Ensure log directory exists
    local log_dir=$(dirname "$logfile")
    [ -d "$log_dir" ] || mkdir -p "$log_dir"
    
    # Add header to log
    echo "=== $desc ($(date)) ===" > "$logfile"
    
    # Execute with output control
    if [ "${VERBOSE:-0}" -eq 1 ]; then
        # Show output in verbose mode
        eval "$cmd" 2>&1 | tee -a "$logfile"
        exit_code=${PIPESTATUS[0]}
    else
        # Hide full output but show progress
        touch "$progress_file"
        
        # Start the command in background and redirect output to both files
        eval "$cmd" > >(tee -a "$logfile" > "$progress_file") 2>&1 &
        local cmd_pid=$!
        
        # Initialize progress display variables
        local spin=('-' '\' '|' '/')
        local i=0
        local start_time=$(date +%s)
        local last_output=""
        local last_percent=""
        local dots=""
        
        # Show a spinner and the last line of output
        while kill -0 $cmd_pid 2>/dev/null; do
            # Get current duration
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local minutes=$((elapsed / 60))
            local seconds=$((elapsed % 60))
            
            # Check if there's any new output
            if [ -f "$progress_file" ]; then
                # Get the last non-empty line
                local new_line=$(tail -n 10 "$progress_file" | grep -v '^$' | tail -n 1)
                if [ -n "$new_line" ]; then
                    # If the line contains any pattern that looks like a percentage, extract it
                    local percent_match=$(echo "$new_line" | grep -o '[0-9]\+%')
                    if [ -n "$percent_match" ]; then
                        last_percent=" $percent_match"
                    fi
                    
                    # Truncate the line if it's too long
                    if [ ${#new_line} -gt 50 ]; then
                        last_output="...${new_line: -50}"
                    else
                        last_output="$new_line"
                    fi
                fi
            fi
            
            # Animate the dots
            dots="${dots}."
            if [ ${#dots} -gt 3 ]; then
                dots="."
            fi
            
            # Update the progress display
            printf "\r${COLOR_BLUE}[%s]${COLOR_RESET} %s %02d:%02d%s %s   " "${spin[$i]}" "$desc" "$minutes" "$seconds" "$last_percent" "$last_output"
            i=$(( (i+1) % 4 ))
            sleep 0.2
        done
        
        # Wait for the command to complete and get its exit code
        wait $cmd_pid
        exit_code=$?
        
        # Clear the progress line
        printf "\r%-100s\r" " "
        
        # If command failed, show the log
        if [ $exit_code -ne 0 ]; then
            log_message "ERROR" "Failed: $desc (Exit code: $exit_code)"
            echo "Last 20 lines of output:"
            tail -n 20 "$logfile"
            log_message "INFO" "Full log available at: $logfile"
        fi
        
        # Remove the temporary progress file
        rm -f "$progress_file" 2>/dev/null
    fi
    
    # Log completion
    if [ $exit_code -eq 0 ]; then
        log_message "INFO" "Completed: $desc"
    fi
    
    return $exit_code
}

# Highlight build output artifacts with their full paths
# Parameters:
#   $1 - Type of artifact (KERNEL, ROOTFS, BUILDROOT, etc.)
#   $2 - Description of the artifact
#   $3 - Full path to the artifact
#   $4 - Optional additional info
highlight_output() {
    local type="$1"
    local description="$2"
    local path="$3"
    local additional_info="${4:-}"
    local box_width=80
    local separator=$(printf '%*s' "$box_width" | tr ' ' '=')
    
    # Only proceed if the file exists
    if [ ! -f "$path" ] && [ ! -d "$path" ]; then
        log_message "WARN" "$type artifact not found: $path"
        return 1
    fi
    
    # Get file size if it's a file
    local size_info=""
    if [ -f "$path" ]; then
        local size=$(du -h "$path" | cut -f1)
        size_info=" (Size: $size)"
    fi
    
    # Output with formatting
    echo -e "\n${COLOR_BOLD}${separator}${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_PURPLE}  $type OUTPUT: ${COLOR_GREEN}$description ${COLOR_RESET}${COLOR_BOLD}$size_info${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  Location: ${COLOR_CYAN}${COLOR_UNDERLINE}$path${COLOR_RESET}"
    
    # Show additional info if provided
    if [ -n "$additional_info" ]; then
        echo -e "${COLOR_BOLD}  Info: ${COLOR_RESET}$additional_info"
    fi
    
    echo -e "${COLOR_BOLD}${separator}${COLOR_RESET}\n"
    
    return 0
}

# Export functions for use in other scripts
export -f install_package
export -f install_dependencies
export -f install_repo_tool
export -f kill_process
export -f run_exec
export -f scan_lan
export -f ensure_directory
export -f setup_gui_config
export -f log_message 
export -f handle_error
export -f check_command
export -f check_file
export -f check_directory
export -f set_log_level
export -f execute_command
export -f highlight_output 