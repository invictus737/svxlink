#!/bin/bash
# docker-build-h3-native-arm.sh - SVXLink build for Orange Pi H3 on macOS Apple Silicon
#
# Optimized for macOS ARM (M1/M2/M3) - NATIVE ARM compilation (NO EMULATION)
# Much faster than Intel Mac: 5-15 minutes vs 20-40 minutes
#
# USAGE:
#   ./docker-build-h3-native-arm.sh
#
# OUTPUT:
#   build-output/svxlink-h3-armhf.tar.gz
#
# Chris YO3TCO

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  SVXLink Build for Orange Pi H3                       ║${NC}"
echo -e "${BLUE}║  macOS Apple Silicon - NATIVE ARM (FAST!)             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# Detect platform
# ============================================================
HOST_ARCH=$(uname -m)

if [[ "$HOST_ARCH" == "arm64" ]]; then
    echo -e "${GREEN}✓ macOS Apple Silicon detected (native ARM)${NC}"
    echo -e "${GREEN}  Build will be FAST (5-15 minutes, no emulation!)${NC}"
    IS_NATIVE_ARM=true
elif [[ "$HOST_ARCH" == "x86_64" ]]; then
    echo -e "${YELLOW}⚠ Intel Mac detected (will use QEMU emulation)${NC}"
    echo -e "${YELLOW}  Build will be SLOW (20-40 minutes)${NC}"
    IS_NATIVE_ARM=false
else
    echo -e "${RED}✗ Unknown architecture: $HOST_ARCH${NC}"
    exit 1
fi

echo ""

# ============================================================
# Configuration
# ============================================================
DOCKERFILE="Dockerfile.armhf"
IMAGE_NAME="svxlink-h3"
PLATFORM="linux/arm/v7"
OUTPUT_DIR="$(pwd)/build-output"

# ============================================================
# Check Docker
# ============================================================
echo -e "${YELLOW}[1/5] Checking Docker...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo -e "${YELLOW}Install Docker Desktop: https://www.docker.com/products/docker-desktop${NC}"
    exit 1
fi

DOCKER_VERSION=$(docker --version)
echo -e "${GREEN}✓ Docker: $DOCKER_VERSION${NC}"

# Check platform support
if docker build --help 2>&1 | grep -q -- "--platform"; then
    echo -e "${GREEN}✓ Platform support available${NC}"
else
    echo -e "${RED}✗ Docker too old (need 20.10+)${NC}"
    exit 1
fi

echo ""

# ============================================================
# Clean
# ============================================================
echo -e "${YELLOW}[2/5] Cleaning previous build...${NC}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo -e "${GREEN}✓ Clean completed${NC}"
echo ""

# ============================================================
# Build
# ============================================================
echo -e "${YELLOW}[3/5] Building Docker image...${NC}"

if [ "$IS_NATIVE_ARM" = true ]; then
    echo -e "${GREEN}Building NATIVELY on ARM (FAST!)${NC}"
    echo -e "${BLUE}Expected time: 5-15 minutes${NC}"
else
    echo -e "${YELLOW}Building with QEMU emulation (SLOW)${NC}"
    echo -e "${BLUE}Expected time: 20-40 minutes${NC}"
fi

echo -e "${BLUE}Platform: $PLATFORM${NC}"
echo ""

START_TIME=$(date +%s)

docker build \
    --platform "$PLATFORM" \
    --file "$DOCKERFILE" \
    --target builder \
    --tag "$IMAGE_NAME:builder" \
    --progress=plain \
    . 2>&1 | tee "$OUTPUT_DIR/docker-build.log"

BUILD_EXIT_CODE=${PIPESTATUS[0]}
END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))
BUILD_MINUTES=$((BUILD_DURATION / 60))
BUILD_SECONDS=$((BUILD_DURATION % 60))

echo ""

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful in ${BUILD_MINUTES}m ${BUILD_SECONDS}s${NC}"

    if [ "$IS_NATIVE_ARM" = true ]; then
        if [ $BUILD_DURATION -gt 1200 ]; then
            echo -e "${YELLOW}⚠ Build took longer than expected (>20 min on native ARM)${NC}"
            echo -e "${YELLOW}  Check Docker Desktop settings (memory, CPU cores)${NC}"
        fi
    fi
else
    echo -e "${RED}✗ Build FAILED${NC}"
    exit 1
fi

echo ""

# ============================================================
# Extract binaries
# ============================================================
echo -e "${YELLOW}[4/5] Extracting binaries...${NC}"

CONTAINER_ID=$(docker create --platform "$PLATFORM" "$IMAGE_NAME:builder")

echo -e "${BLUE}Copying files from container...${NC}"
docker cp "$CONTAINER_ID:/build/install" "$OUTPUT_DIR/install"
docker cp "$CONTAINER_ID:/build/build.log" "$OUTPUT_DIR/build.log"

docker rm "$CONTAINER_ID" > /dev/null

# Create tarball
cd "$OUTPUT_DIR"
tar czf svxlink-h3-armhf.tar.gz -C install .
rm -rf install
cd - > /dev/null

echo -e "${GREEN}✓ Binaries extracted${NC}"
echo ""

# ============================================================
# Verify
# ============================================================
echo -e "${YELLOW}[5/5] Verifying output...${NC}"

if [ -f "$OUTPUT_DIR/svxlink-h3-armhf.tar.gz" ]; then
    SIZE=$(du -h "$OUTPUT_DIR/svxlink-h3-armhf.tar.gz" | awk '{print $1}')
    echo -e "${GREEN}✓ Tarball: svxlink-h3-armhf.tar.gz ($SIZE)${NC}"

    # Extract for inspection
    cd "$OUTPUT_DIR"
    tar xzf svxlink-h3-armhf.tar.gz

    if [ -f "opt/rolink/bin/svxlink" ]; then
        echo -e "${GREEN}✓ Binary: opt/rolink/bin/svxlink${NC}"

        # Show file info
        FILE_INFO=$(file opt/rolink/bin/svxlink)
        echo -e "${BLUE}  $FILE_INFO${NC}"

        # Show size
        SIZE_BIN=$(ls -lh opt/rolink/bin/svxlink | awk '{print $5}')
        echo -e "${BLUE}  Size: $SIZE_BIN${NC}"
    fi

    cd - > /dev/null
else
    echo -e "${RED}✗ Tarball not found${NC}"
    exit 1
fi

# Check NEON optimization
if [ -f "$OUTPUT_DIR/build.log" ]; then
    echo ""
    echo -e "${BLUE}NEON optimization check:${NC}"
    if grep -q "STRONG NEON" "$OUTPUT_DIR/build.log"; then
        NEON_LINE=$(grep "STRONG NEON" "$OUTPUT_DIR/build.log")
        echo -e "${GREEN}  $NEON_LINE${NC}"
    elif grep -q "MODERATE NEON" "$OUTPUT_DIR/build.log"; then
        NEON_LINE=$(grep "MODERATE NEON" "$OUTPUT_DIR/build.log")
        echo -e "${YELLOW}  $NEON_LINE${NC}"
    elif grep -q "NO NEON" "$OUTPUT_DIR/build.log"; then
        NEON_LINE=$(grep "NO NEON" "$OUTPUT_DIR/build.log")
        echo -e "${RED}  $NEON_LINE${NC}"
    fi
fi

echo ""

# ============================================================
# Success
# ============================================================
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           BUILD SUCCESSFUL!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}Build completed in: ${BUILD_MINUTES}m ${BUILD_SECONDS}s${NC}"

if [ "$IS_NATIVE_ARM" = true ]; then
    echo -e "${GREEN}Native ARM compilation - FAST!${NC}"
else
    echo -e "${YELLOW}QEMU emulation - consider using Apple Silicon Mac for faster builds${NC}"
fi

echo ""
echo -e "${BLUE}Output directory: $OUTPUT_DIR${NC}"
echo ""
echo -e "${YELLOW}Files created:${NC}"
echo -e "  📦 svxlink-h3-armhf.tar.gz (binare compilate)"
echo -e "  📄 build.log (log compilare)"
echo -e "  📂 opt/rolink/ (fișiere extrase)"
echo ""

echo -e "${YELLOW}Next: Transfer to Orange Pi${NC}"
echo -e "  ${BLUE}scp build-output/svxlink-h3-armhf.tar.gz pi@OPI_IP:/tmp/${NC}"
echo ""
