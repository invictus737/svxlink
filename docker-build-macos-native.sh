#!/bin/bash
# docker-build-macos-native.sh - TRUE native ARM64 build for macOS Apple Silicon
#
# Container: ARM64 Debian (NATIVE on macOS M1/M2/M3 - NO emulation!)
# Cross-compile: ARM64 → ARMv7 (for Orange Pi H3)
# Result: FASTEST possible build (2-10 minutes!)
#
# USAGE:
#   ./docker-build-macos-native.sh
#
# Chris YO3TCO

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  SVXLink Build - macOS Apple Silicon NATIVE           ║${NC}"
echo -e "${BLUE}║  ARM64 container + ARMv7 cross-compilation             ║${NC}"
echo -e "${BLUE}║  FASTEST METHOD (2-10 minutes!)                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# Detect platform
# ============================================================
HOST_ARCH=$(uname -m)

if [[ "$HOST_ARCH" != "arm64" ]]; then
    echo -e "${RED}✗ This script requires macOS Apple Silicon (arm64)${NC}"
    echo -e "${RED}  Current architecture: $HOST_ARCH${NC}"
    exit 1
fi

echo -e "${GREEN}✓ macOS Apple Silicon detected${NC}"
echo -e "${GREEN}  Container will run NATIVELY (ARM64)${NC}"
echo -e "${GREEN}  Cross-compilation: ARM64 → ARMv7 (Orange Pi H3)${NC}"
echo ""

# ============================================================
# Configuration
# ============================================================
DOCKERFILE="Dockerfile.arm64-cross"
IMAGE_NAME="svxlink-h3"
OUTPUT_DIR="$(pwd)/build-output"

# ============================================================
# Check Docker
# ============================================================
echo -e "${YELLOW}[1/5] Checking Docker...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker: $(docker --version)${NC}"

# Verify ARM64 support
DOCKER_ARCH=$(docker version --format '{{.Server.Arch}}')
if [[ "$DOCKER_ARCH" != "arm64" ]]; then
    echo -e "${YELLOW}⚠ Docker reports arch: $DOCKER_ARCH${NC}"
fi

echo ""

# ============================================================
# Clean
# ============================================================
echo -e "${YELLOW}[2/5] Cleaning...${NC}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Remove old images
docker rmi -f "$IMAGE_NAME:builder" "$IMAGE_NAME:export" 2>/dev/null || true

echo -e "${GREEN}✓ Clean completed${NC}"
echo ""

# ============================================================
# Build
# ============================================================
echo -e "${YELLOW}[3/5] Building Docker image (NATIVE ARM64)...${NC}"
echo -e "${BLUE}Container: ARM64 Debian (native on macOS)${NC}"
echo -e "${BLUE}Cross-compile: ARM64 → ARMv7 (Orange Pi H3)${NC}"
echo -e "${BLUE}Expected time: 2-10 minutes${NC}"
echo ""

START_TIME=$(date +%s)

# Build WITHOUT --platform flag (uses native architecture)
docker build \
    --file "$DOCKERFILE" \
    --target builder \
    --tag "$IMAGE_NAME:builder" \
    . 2>&1 | tee "$OUTPUT_DIR/docker-build.log"

BUILD_EXIT_CODE=${PIPESTATUS[0]}
END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))
BUILD_MINUTES=$((BUILD_DURATION / 60))
BUILD_SECONDS=$((BUILD_DURATION % 60))

echo ""

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful in ${BUILD_MINUTES}m ${BUILD_SECONDS}s${NC}"

    if [ $BUILD_DURATION -lt 120 ]; then
        echo -e "${GREEN}  EXCELLENT: Very fast build!${NC}"
    elif [ $BUILD_DURATION -lt 600 ]; then
        echo -e "${GREEN}  GOOD: Fast native build${NC}"
    else
        echo -e "${YELLOW}  ⚠ Slower than expected (>10 min)${NC}"
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

CONTAINER_ID=$(docker create "$IMAGE_NAME:builder")

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

        FILE_INFO=$(file opt/rolink/bin/svxlink)
        echo -e "${BLUE}  $FILE_INFO${NC}"

        # Check that it's ARMv7 (not ARM64!)
        if echo "$FILE_INFO" | grep -q "ARM.*EABI5"; then
            echo -e "${GREEN}  ✓ Correct architecture: ARMv7 (32-bit) for Orange Pi H3${NC}"
        else
            echo -e "${RED}  ✗ WARNING: Unexpected architecture${NC}"
        fi
    fi

    cd - > /dev/null
fi

# Check NEON
if [ -f "$OUTPUT_DIR/build.log" ]; then
    echo ""
    echo -e "${BLUE}NEON optimization check:${NC}"
    if grep -q "STRONG NEON" "$OUTPUT_DIR/build.log"; then
        grep "STRONG NEON" "$OUTPUT_DIR/build.log" | sed 's/^/  /'
    elif grep -q "MODERATE NEON" "$OUTPUT_DIR/build.log"; then
        grep "MODERATE NEON" "$OUTPUT_DIR/build.log" | sed 's/^/  /'
    elif grep -q "NO NEON" "$OUTPUT_DIR/build.log"; then
        grep "NO NEON" "$OUTPUT_DIR/build.log" | sed 's/^/  /'
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

echo -e "${BLUE}Build method: Native ARM64 + cross-compilation${NC}"
echo -e "${BLUE}Build time: ${BUILD_MINUTES}m ${BUILD_SECONDS}s${NC}"
echo -e "${BLUE}Container architecture: ARM64 (native on macOS)${NC}"
echo -e "${BLUE}Output architecture: ARMv7 (Orange Pi H3)${NC}"
echo ""

echo -e "${BLUE}Output: $OUTPUT_DIR${NC}"
echo ""
echo -e "${YELLOW}Files:${NC}"
echo -e "  📦 svxlink-h3-armhf.tar.gz"
echo -e "  📄 build.log"
echo -e "  📂 opt/rolink/"
echo ""

echo -e "${YELLOW}Transfer to Orange Pi:${NC}"
echo -e "  ${BLUE}scp build-output/svxlink-h3-armhf.tar.gz pi@OPI_IP:/tmp/${NC}"
echo ""
