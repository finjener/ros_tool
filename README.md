# ROS Tool - Embedded Linux Build System

## Overview

ROS Tool is a comprehensive build and configuration tool for embedded Linux systems. It runs the complete process of building, configuring, and deploying embedded Linux systems for target hardware platforms. The tool handles kernel compilation, buildroot setup, rootfs generation, and device flashing for platforms like Radxa and Raspberry Pi 3. It is an automation tool for custom embedded linux system creation for the boards.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          run.sh (Main Entry)                    │
├─────────────┬─────────────┬────────────┬───────────┬────────────┤
│             │             │            │           │            │
▼             ▼             ▼            ▼           ▼            ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│ kernel_ │ │buildroot│ │rootfs.sh│ │flash.sh │ │clean.sh │ │config.sh│
│build.sh │ │.sh      │ │         │ │         │ │         │ │         │
└────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
     │           │           │           │           │           │
     └───────────┴───────────┴──────────►│◄──────────┴───────────┘
                                         │
                                         ▼
                                     ┌─────────┐
                                     │utils.sh │
                                     │         │
                                     └─────────┘
```

The architecture follows a modular design where:

- `run.sh` acts as the main entry point, coordinating the entire build workflow
- Individual modules handle specific parts of the build process
- `utils.sh` provides shared utilities used by all modules
- `config.sh` defines configuration parameters for the build process
- All modules leverage the common error handling and logging framework

## Build Process Flow

```
┌────────────┐     ┌──────────────┐     ┌────────────────┐     ┌───────────────┐     ┌────────────┐
│  Parse     │     │  Validate    │     │  Build Kernel  │     │ Setup         │     │  Generate  │
│ Parameters ├────►│  Parameters  ├────►│  (if requested)├────►│ Buildroot     ├────►│  Rootfs    │
└────────────┘     └──────────────┘     └────────────────┘     └───────────────┘     └─────┬──────┘
                                                                                           │
                                         ┌────────────────┐     ┌───────────────┐          │
                                         │  Exit with     │     │  Flash Device │          │
                                         │  Status Code   │◄────│ (if requested)│◄─────────┘
                                         └────────────────┘     └───────────────┘
```

The build process follows these steps:

1. Parse command-line arguments to determine build options
2. Validate parameters and perform any requested cleaning
3. Build the kernel if requested
4. Set up and configure Buildroot for the target platform
5. Generate the root filesystem image
6. Package firmware and flash the device if requested
7. Exit with appropriate status code

## Module Descriptions

### 1. run.sh - Main Controller

The central script that orchestrates the entire build process. It:

- Parses command-line arguments
- Validates parameters
- Loads all required modules
- Coordinates the build workflow
- Handles error conditions
- Provides user feedback

The script supports both modern parameter styles (`--option value`) and legacy parameter styles for backward compatibility.

### 2. kernel_build.sh - Kernel Compilation

Manages the process of building the Linux kernel for the target platform:

- Selects and sets up the cross-compiler toolchain
- Clones or validates the kernel repository
- Sets up the initial RAM disk (initrd)
- Applies kernel configuration
- Builds the kernel and modules
- Creates the bootable image

Key functions:
- `compile_kernel()`: Main entry point for kernel compilation
- `setup_compiler()`: Configures the cross-compilation toolchain
- `setup_initrd()`: Creates the initial RAM disk
- `setup_kernel_config()`: Handles kernel configuration
- `build_kernel()`: Performs the actual kernel compilation
- `create_boot_image()`: Creates the final bootable image

### 3. buildroot.sh - Root Filesystem Build System

Handles the setup, configuration, and build process for Buildroot:

- Downloads and extracts Buildroot
- Configures Buildroot for specific targets (Radxa, Raspberry Pi 3)
- Builds the Buildroot system
- Manages existing Buildroot installations

Key functions:
- `setup_buildroot()`: Main entry point for Buildroot setup
- `handle_existing_buildroot()`: Handles existing Buildroot installations
- `download_and_setup_buildroot()`: Sets up fresh Buildroot installations
- `offer_rebuild_buildroot()`: Provides options to rebuild with different configurations

### 4. rootfs.sh - Root Filesystem Generation

Creates the root filesystem image:

- Cleans up existing mounts and old files
- Creates a new ext4 image file
- Mounts the image file
- Extracts the Buildroot-generated rootfs tarball
- Installs kernel modules and firmware
- Unmounts and finalizes the image

Key functions:
- `rootfs_image_generate()`: Main entry point for rootfs generation
- `cleanup_mounts()`: Ensures clean unmounting
- `cleanup_old_files()`: Removes old image files
- `create_rootfs_image()`: Creates the ext4 filesystem
- `install_modules_and_firmware()`: Installs kernel modules
- `cleanup_after_build()`: Finalizes the image and cleans up

### 5. flash.sh - Device Flashing

Packages and flashes firmware to target devices:

- Verifies required components and tools
- Packages components into an update.img file
- Optionally flashes to a connected device

Key functions:
- `package_and_flash()`: Main entry point for firmware packaging and flashing
- `create_update_img()`: Creates the flashable image
- `flash_device()`: Flashes the image to the device

### 6. clean.sh - Cleaning Utilities

Provides functions for cleaning build artifacts:

- Targeted cleaning for individual components
- Comprehensive cleaning options (normal or deep)
- Safe cleanup with error handling

Key functions:
- `clean_kernel()`: Cleans kernel build artifacts
- `clean_buildroot()`: Cleans Buildroot artifacts
- `clean_rootfs()`: Cleans rootfs artifacts and unmounts filesystems
- `clean_flash()`: Cleans flash artifacts
- `clean_all()`: Performs complete cleanup

### 7. utils.sh - Shared Utilities

Provides shared utility functions used by all modules:

- Logging and error handling
- Command execution and progress display
- Dependency checking
- Directory and file operations

## Directory Structure

```
ros_tool/
├── run.sh                   # Main script
├── scripts/
│   ├── utils.sh             # Shared utilities
│   ├── kernel_build.sh      # Kernel compilation
│   ├── buildroot.sh         # Buildroot management
│   ├── rootfs.sh            # Rootfs generation
│   ├── flash.sh             # Device flashing
│   ├── clean.sh             # Cleanup utilities
│   └── config.sh            # Configuration variables
├── conf/                    # Default configurations
└── rockchip-tools/          # Flashing utilities
    ├── Linux/               # Output directory for images
    ├── mkupdate.sh          # Update image creation script
    └── upgrade_tool         # Flashing tool
```

## Target Platforms

Currently, the tool supports the following platforms:

1. **Radxa Rock Pro** - A Rockchip RK3188 based development board
2. **Raspberry Pi 3** - Popular ARM-based single-board computer

## Usage Examples

### Building a kernel for Raspberry Pi 3:
```bash
./run.sh --kernel --target=rasp3
```

### Building a kernel and generating a rootfs:
```bash
./run.sh --kernel --target=rasp3 --pack
```

### Building and flashing a complete system for Radxa:
```bash
./run.sh --kernel --target=radxa --pack-radxa --flash
```

### Cleaning the workspace:
```bash
./run.sh --clean normal
```

### Deep cleaning all build artifacts:
```bash
./run.sh --clean deep
```

## Error Handling

The system includes robust error handling:

1. **Input Validation Check**: Validates parameters and file existence
2. **Process Verification**: Verifies command execution and tool availability
3. **Fail Information**: Provides helpful error messages and attempts recovery
4. **Status Information**: Returns meaningful error codes

## Requirements

- Bash 4.0+
- Ubuntu 14.04 / 16.04 / 20.04
- Core utilities: git, make, tar, wget, etc.
- ARM cross-compiler toolchains
- Qt development tools for Buildroot configuration
- Sufficient disk space (10GB+ recommended)
- Sufficient RAM (4GB+ recommended)

## Installation

No special installation is required. Simply clone the repository:

```bash
git clone https://github.com/sf044/ros_tool.git
cd ros_tool
```

The tool will automatically install required dependencies when first run.

## Troubleshooting

### Common Issues

1. **Cross-compiler errors**: 
   - Ensure the selected compiler is compatible with your target
   - Check network connectivity when downloading compilers

2. **Buildroot configuration errors**:
   - Verify Qt development tools are installed for xconfig
   - Ensure default configuration for your target exists

3. **Flashing errors**:
   - Check that the device is properly connected and in maskrom mode
   - Verify user has appropriate permissions (dialout group)

4. **Resource limitations**:
   - Build processes can be memory-intensive; ensure sufficient resources

### Log Files

The build process creates detailed logs that can help diagnose issues:
- Standard log: `build.log` in the project root
- Component-specific logs in their respective directories

