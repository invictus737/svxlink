#!/bin/bash
# build_orangepi_h3.sh - SVXLink optimized build for Orange Pi Zero (Allwinner H3)
#
# TARGET: ARM Cortex-A7 (ARMv7-A with NEON)
# CPU: Allwinner H3 (quad-core 1.2GHz)
# ARCH: armhf (32-bit ARM with hardware floating point)
#
# USAGE:
#   1. Copy this script to Orange Pi Zero
#   2. chmod +x build_orangepi_h3.sh
#   3. ./build_orangepi_h3.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  SVXLink Build for Orange Pi Zero (Allwinner H3)      ║${NC}"
echo -e "${BLUE}║  Target: ARM Cortex-A7 + NEON optimization            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# STEP 1: Verify we're on ARM platform
# ============================================================
echo -e "${YELLOW}[1/7] Verifying platform...${NC}"

ARCH=$(uname -m)
if [[ "$ARCH" != "armv7l" && "$ARCH" != "armhf" ]]; then
  echo -e "${RED}ERROR: This script must run on ARM platform (armv7l/armhf)${NC}"
  echo -e "${RED}Current architecture: $ARCH${NC}"
  echo ""
  echo -e "${YELLOW}If you're on Orange Pi Zero, you should see 'armv7l'${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Platform verified: $ARCH${NC}"

# Check for H3 CPU
if grep -q "sun8i-h3" /proc/device-tree/compatible 2>/dev/null; then
  echo -e "${GREEN}✓ Allwinner H3 detected${NC}"
elif grep -q "Allwinner sun8i Family" /proc/cpuinfo 2>/dev/null; then
  echo -e "${GREEN}✓ Allwinner SoC detected${NC}"
else
  echo -e "${YELLOW}⚠ Could not detect H3, continuing anyway...${NC}"
fi

# CPU info
CPU_COUNT=$(nproc)
echo -e "${GREEN}✓ CPU cores: $CPU_COUNT${NC}"
echo ""

# ============================================================
# STEP 2: Install build dependencies
# ============================================================
echo -e "${YELLOW}[2/7] Installing build dependencies...${NC}"

# Detect package manager
if command -v apt-get &> /dev/null; then
  PKG_MANAGER="apt-get"
elif command -v dnf &> /dev/null; then
  PKG_MANAGER="dnf"
elif command -v yum &> /dev/null; then
  PKG_MANAGER="yum"
else
  echo -e "${RED}ERROR: No supported package manager found${NC}"
  exit 1
fi

echo -e "${BLUE}Package manager: $PKG_MANAGER${NC}"

# Update package lists
if [ "$PKG_MANAGER" = "apt-get" ]; then
  sudo apt-get update
fi

# Install dependencies
echo -e "${BLUE}Installing required packages...${NC}"

PACKAGES=(
  # Build essentials
  build-essential
  cmake
  git
  pkg-config

  # SVXLink core dependencies
  libsigc++-2.0-dev
  libgsm1-dev
  libpopt-dev
  libgcrypt20-dev
  libspeex-dev
  libasound2-dev

  # Audio codecs
  libopus-dev

  # TCL for event handling
  tcl-dev
  tcl8.6

  # Network
  libcurl4-openssl-dev

  # Optional but recommended
  groff
  doxygen

  # Performance tools
  ccache
)

for pkg in "${PACKAGES[@]}"; do
  if ! dpkg -l | grep -q "^ii  $pkg"; then
    echo -e "${BLUE}Installing $pkg...${NC}"
    sudo $PKG_MANAGER install -y "$pkg" || {
      echo -e "${YELLOW}⚠ Warning: Could not install $pkg (continuing)${NC}"
    }
  else
    echo -e "${GREEN}✓ $pkg already installed${NC}"
  fi
done

echo -e "${GREEN}✓ Dependencies installed${NC}"
echo ""

# ============================================================
# STEP 3: Prepare build environment
# ============================================================
echo -e "${YELLOW}[3/7] Preparing build environment...${NC}"

# Determine source directory
if [ -d "/private/tmp/svxlink" ]; then
  SRC_DIR="/private/tmp/svxlink"
elif [ -d "$HOME/svxlink" ]; then
  SRC_DIR="$HOME/svxlink"
elif [ -d "$(pwd)/svxlink" ]; then
  SRC_DIR="$(pwd)/svxlink"
else
  echo -e "${YELLOW}⚠ SVXLink source not found, cloning...${NC}"
  SRC_DIR="$HOME/svxlink-build"
  git clone https://github.com/sm0svx/svxlink.git "$SRC_DIR"
  cd "$SRC_DIR"
  git checkout master  # Or specific branch
fi

echo -e "${GREEN}✓ Source directory: $SRC_DIR${NC}"

# Create build directory
BUILD_DIR="$SRC_DIR/src/build-orangepi-h3"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo -e "${GREEN}✓ Build directory: $BUILD_DIR${NC}"
echo ""

# ============================================================
# STEP 4: Configure CMake with H3 optimizations
# ============================================================
echo -e "${YELLOW}[4/7] Configuring CMake with ARM Cortex-A7 optimizations...${NC}"

# ARM Cortex-A7 specific compiler flags
# - march=armv7-a: Target ARMv7-A architecture
# - mtune=cortex-a7: Optimize for Cortex-A7 microarchitecture
# - mfpu=neon-vfpv4: Use NEON SIMD + VFPv4 floating point
# - mfloat-abi=hard: Hardware floating point ABI
# - O3: Maximum optimization
# - ftree-vectorize: Auto-vectorization for NEON
# - ffast-math: Fast floating point (trade accuracy for speed)

CFLAGS="-march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -O3 -ftree-vectorize -ffast-math -pipe"
CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O1 -Wl,--as-needed"

echo -e "${BLUE}CFLAGS: $CFLAGS${NC}"
echo -e "${BLUE}CXXFLAGS: $CXXFLAGS${NC}"
echo -e "${BLUE}LDFLAGS: $LDFLAGS${NC}"
echo ""

# CMake configuration
cmake \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DSYSCONF_INSTALL_DIR=/etc \
  -DLOCAL_STATE_DIR=/var \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$CFLAGS" \
  -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
  -DUSE_QT=OFF \
  -DUSE_OPUS=ON \
  -DUSE_SPEEX=ON \
  ..

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ CMake configuration successful${NC}"
else
  echo -e "${RED}✗ CMake configuration FAILED${NC}"
  exit 1
fi

echo ""

# ============================================================
# STEP 5: Compile with NEON optimizations
# ============================================================
echo -e "${YELLOW}[5/7] Compiling SVXLink (this will take 15-30 minutes)...${NC}"

# Use ccache if available for faster rebuilds
if command -v ccache &> /dev/null; then
  export CC="ccache gcc"
  export CXX="ccache g++"
  echo -e "${BLUE}Using ccache for faster compilation${NC}"
fi

# Compile with all CPU cores
JOBS=$CPU_COUNT
echo -e "${BLUE}Building with $JOBS parallel jobs...${NC}"
echo ""

# Show progress
make -j$JOBS 2>&1 | tee build.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✓ Compilation successful!${NC}"
else
  echo ""
  echo -e "${RED}✗ Compilation FAILED${NC}"
  echo -e "${RED}Check build.log for details${NC}"
  exit 1
fi

echo ""

# ============================================================
# STEP 6: Install binaries
# ============================================================
echo -e "${YELLOW}[6/7] Installing SVXLink...${NC}"

sudo make install

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Installation successful${NC}"
else
  echo -e "${RED}✗ Installation FAILED${NC}"
  exit 1
fi

# Install systemd service files
if [ -d "/lib/systemd/system" ]; then
  echo -e "${BLUE}Installing systemd service files...${NC}"
  sudo cp -f $SRC_DIR/src/svxlink/systemd/*.service /lib/systemd/system/ 2>/dev/null || true
  sudo systemctl daemon-reload
  echo -e "${GREEN}✓ Systemd services installed${NC}"
fi

echo ""

# ============================================================
# STEP 7: Verify installation
# ============================================================
echo -e "${YELLOW}[7/7] Verifying installation...${NC}"

# Check svxlink binary
if command -v svxlink &> /dev/null; then
  VERSION=$(svxlink --version 2>&1 | head -1)
  echo -e "${GREEN}✓ SVXLink installed: $VERSION${NC}"
else
  echo -e "${RED}✗ SVXLink binary not found${NC}"
  exit 1
fi

# Check libraries
echo -e "${BLUE}Checking shared libraries...${NC}"
ldd $(which svxlink) | grep -E "libasync|libecholib" && echo -e "${GREEN}✓ SVXLink libraries linked${NC}"

# Check NEON support in binary
echo -e "${BLUE}Checking ARM NEON usage...${NC}"
if objdump -d $(which svxlink) 2>/dev/null | grep -q "vfma\|vmla\|vadd"; then
  echo -e "${GREEN}✓ NEON instructions detected in binary${NC}"
else
  echo -e "${YELLOW}⚠ NEON instructions not detected (may not be optimized)${NC}"
fi

echo ""

# ============================================================
# SUCCESS
# ============================================================
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           BUILD SUCCESSFUL!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Build optimizations applied:${NC}"
echo -e "  - ARM Cortex-A7 tuning (-mtune=cortex-a7)"
echo -e "  - NEON SIMD vectorization (-mfpu=neon-vfpv4)"
echo -e "  - Hardware floating point (-mfloat-abi=hard)"
echo -e "  - Maximum optimization (-O3 -ftree-vectorize)"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Configure SVXLink: sudo nano /etc/svxlink/svxlink.conf"
echo -e "  2. Start service: sudo systemctl start svxlink"
echo -e "  3. Check status: sudo systemctl status svxlink"
echo -e "  4. View logs: sudo journalctl -u svxlink -f"
echo ""
echo -e "${YELLOW}Configuration files:${NC}"
echo -e "  Main config: /etc/svxlink/svxlink.conf"
echo -e "  GPIO config: /etc/svxlink/gpio.conf"
echo -e "  Module path: /usr/lib/svxlink"
echo ""
echo -e "${GREEN}Build log saved to: $BUILD_DIR/build.log${NC}"
echo ""
