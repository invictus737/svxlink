#!/bin/bash
# docker-build-h3-simple.sh - Simplified Docker build for Orange Pi H3
#
# Works without buildx - uses standard docker build with --platform
# For Docker Desktop 20.10+
#
# USAGE:
#   ./docker-build-h3-simple.sh
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
echo -e "${BLUE}║  SVXLink Docker Build for Orange Pi Zero (H3)         ║${NC}"
echo -e "${BLUE}║  Simplified build (no buildx required)                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Configuration
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
    exit 1
fi

DOCKER_VERSION=$(docker --version)
echo -e "${GREEN}✓ Docker found: $DOCKER_VERSION${NC}"

# Check if Docker supports --platform
if docker build --help 2>&1 | grep -q -- "--platform"; then
    echo -e "${GREEN}✓ Platform support available${NC}"
else
    echo -e "${RED}✗ Docker version too old (need 20.10+)${NC}"
    exit 1
fi

echo ""

# ============================================================
# Clean previous build
# ============================================================
echo -e "${YELLOW}[2/5] Cleaning previous build...${NC}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo -e "${GREEN}✓ Clean completed${NC}"
echo ""

# ============================================================
# Build stage 1: Builder
# ============================================================
echo -e "${YELLOW}[3/5] Building Docker image (20-40 minutes)...${NC}"
echo -e "${BLUE}Building for platform: $PLATFORM${NC}"
echo ""

# Note: Docker Desktop will automatically use QEMU for ARM emulation
docker build \
    --platform "$PLATFORM" \
    --file "$DOCKERFILE" \
    --target builder \
    --tag "$IMAGE_NAME:builder" \
    . 2>&1 | tee "$OUTPUT_DIR/docker-build.log"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo -e "${RED}✗ Build FAILED${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Build successful${NC}"
echo ""

# ============================================================
# Extract binaries from builder
# ============================================================
echo -e "${YELLOW}[4/5] Extracting binaries...${NC}"

# Create temporary container and copy files
CONTAINER_ID=$(docker create --platform "$PLATFORM" "$IMAGE_NAME:builder")

echo -e "${BLUE}Copying files from container...${NC}"
docker cp "$CONTAINER_ID:/build/install" "$OUTPUT_DIR/install"
docker cp "$CONTAINER_ID:/build/build.log" "$OUTPUT_DIR/build.log"

# Clean up container
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
    echo -e "${GREEN}✓ Tarball created: svxlink-h3-armhf.tar.gz ($SIZE)${NC}"

    # Extract for inspection
    cd "$OUTPUT_DIR"
    tar xzf svxlink-h3-armhf.tar.gz

    if [ -f "opt/rolink/bin/svxlink" ]; then
        echo -e "${GREEN}✓ Binary: opt/rolink/bin/svxlink${NC}"
        file opt/rolink/bin/svxlink | sed 's/^/  /'
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

echo -e "${BLUE}Output directory: $OUTPUT_DIR${NC}"
echo ""
echo -e "${YELLOW}Files:${NC}"
echo -e "  📦 svxlink-h3-armhf.tar.gz"
echo -e "  📄 build.log"
echo -e "  📂 opt/rolink/"
echo ""

echo -e "${YELLOW}Next: Transfer to Orange Pi${NC}"
echo -e "  ${BLUE}scp build-output/svxlink-h3-armhf.tar.gz pi@OPI_IP:/tmp/${NC}"
echo ""
