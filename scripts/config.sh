#!/bin/bash

# Configuration File
# ---------------------------

# Buildroot versions
BUILDROOT_VERSIONS=(
  "buildroot-2021.02.8"
  "2021"
)

# Package lists
COMMON_PACKAGES=( 
  "bc" 
  "bison" 
  "build-essential" 
  "curl"
  "device-tree-compiler" 
  "dosfstools" 
  "flex" 
  "gcc-aarch64-linux-gnu"
  "gcc-arm-linux-gnueabihf" 
  "gdisk" 
  "git" 
  "gnupg" 
  "gperf" 
  "libc6-dev"
  "libncurses5-dev" 
  "libssl-dev"
  "lzop" 
  "mtools" 
  "parted" 
  "swig" 
  "tar" 
  "zip" 
  "qtbase5-dev" 
  "qemu-user-static" 
  "binfmt-support"
  "libglade2-dev" 
  "libglib2.0-dev" 
  "libgtk2.0-dev" 
  "libpython2-dev"
)

UBUNTU20_PACKAGES=(
  "mkbootimg"
  "libcrypt1"
  "libcrypto++-dev"
  "libcrypto++-utils"
  # Note: "repo" is installed manually via script, not through apt
)

UBUNTU14_PACKAGES=(
  "qt4-default" 
  "libc6:i386" 
  "libssl1.0.0" 
  "libpython-dev" 
  "nautilus-open-terminal"
)

# Kernel configuration
KERNEL_REPO="https://www.github.com/ferhatsencer/linux-rockchip.git"
KERNEL_BRANCH="radxa-stable-3.0"
KERNEL_DIR="linux-radxa-stable-3.0"

# File paths
DEFAULT_KERNEL_CONFIG="conf/rockchip-default_defconfig"
RADXA_BUILDROOT_CONFIG="conf/radxa-buildroot-2021.02.8_default_defconfig"
RASP3_BUILDROOT_CONFIG="conf/rasp3-buildroot-2021.02.8_default_defconfig"

# Compiler URLs
GCC_48_URL="https://releases.linaro.org/archive/13.08/components/toolchain/binaries/gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux.tar.xz"
GCC_49_URL="https://releases.linaro.org/components/toolchain/binaries/latest-4/arm-linux-gnueabihf/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz"
ARM_EABI_REPO="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6"

# Image generation settings
ROOTFS_SIZE_MB=250
ROOTFS_LABEL="linuxroot"

# Tools directory
ROCKCHIP_TOOLS_DIR="rockchip-tools"
ROCKCHIP_LINUX_DIR="$ROCKCHIP_TOOLS_DIR/Linux"

# Bootloader file
BOOTLOADER_BIN="RK3188Loader(L)_V2.19.bin" 