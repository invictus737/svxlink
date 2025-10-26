#!/bin/bash
# docker-build-h3.sh - Build SVXLink for Orange Pi Zero (H3) using Docker
#
# Cross-compile SVXLink for ARM Cortex-A7 with NEON optimizations
# Runs on macOS/Linux x86_64 and produces armhf binaries
#
# USAGE:
#   ./docker-build-h3.sh
#
# OUTPUT:
#   build-output/svxlink-h3-armhf.tar.gz - Compiled binaries
#   build-output/build.log - Build log
#
# Chris YO3TCO

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  SVXLink Docker Build for Orange Pi Zero (H3)         ║${NC}"
echo -e "${BLUE}║  Cross-compilation: x86_64 → armhf (ARMv7 + NEON)     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# Configuration
# ============================================================
DOCKERFILE="Dockerfile.armhf"
IMAGE_NAME="svxlink-h3"
IMAGE_TAG="latest"
PLATFORM="linux/arm/v7"
OUTPUT_DIR="$(pwd)/build-output"

# ============================================================
# Check prerequisites
# ============================================================
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo -e "${YELLOW}Install Docker Desktop: https://www.docker.com/products/docker-desktop${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker found: $(docker --version)${NC}"

# Check Dockerfile
if [ ! -f "$DOCKERFILE" ]; then
    echo -e "${RED}✗ Dockerfile not found: $DOCKERFILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dockerfile found: $DOCKERFILE${NC}"

# Check source directory
if [ ! -d "src" ]; then
    echo -e "${RED}✗ Source directory 'src' not found${NC}"
    echo -e "${YELLOW}Run this script from SVXLink repository root${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Source directory found${NC}"

echo ""

# ============================================================
# Setup Docker buildx
# ============================================================
echo -e "${YELLOW}[2/6] Setting up Docker buildx...${NC}"

# Check if buildx is available
if ! docker buildx version &> /dev/null; then
    echo -e "${RED}✗ Docker buildx not available${NC}"
    echo -e "${YELLOW}Update Docker Desktop to latest version${NC}"
    exit 1
fi

# Create builder instance if not exists
if ! docker buildx inspect svxlink-builder &> /dev/null; then
    echo -e "${BLUE}Creating buildx instance: svxlink-builder${NC}"
    docker buildx create --name svxlink-builder --use
else
    echo -e "${BLUE}Using existing buildx instance: svxlink-builder${NC}"
    docker buildx use svxlink-builder
fi

# Bootstrap builder (download QEMU emulators for ARM)
echo -e "${BLUE}Bootstrapping builder (downloading ARM emulator)...${NC}"
docker buildx inspect --bootstrap

echo -e "${GREEN}✓ Docker buildx ready${NC}"
echo ""

# ============================================================
# Clean previous build
# ============================================================
echo -e "${YELLOW}[3/6] Cleaning previous build...${NC}"

# Clean output directory
if [ -d "$OUTPUT_DIR" ]; then
    echo -e "${BLUE}Removing old build output...${NC}"
    rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"

# Clean old Docker images (optional)
if docker images | grep -q "$IMAGE_NAME"; then
    echo -e "${BLUE}Removing old Docker image...${NC}"
    docker rmi -f "$IMAGE_NAME:$IMAGE_TAG" 2>/dev/null || true
fi

echo -e "${GREEN}✓ Clean completed${NC}"
echo ""

# ============================================================
# Build Docker image
# ============================================================
echo -e "${YELLOW}[4/6] Building Docker image for $PLATFORM...${NC}"
echo -e "${BLUE}This will take 20-40 minutes (cross-compilation is slow)${NC}"
echo ""

# Build with progress output
docker buildx build \
    --platform "$PLATFORM" \
    --file "$DOCKERFILE" \
    --target export \
    --tag "$IMAGE_NAME:$IMAGE_TAG" \
    --progress=plain \
    --load \
    . 2>&1 | tee "$OUTPUT_DIR/docker-build.log"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Docker build successful${NC}"
else
    echo ""
    echo -e "${RED}✗ Docker build FAILED${NC}"
    echo -e "${RED}Check logs: $OUTPUT_DIR/docker-build.log${NC}"
    exit 1
fi

echo ""

# ============================================================
# Extract binaries from image
# ============================================================
echo -e "${YELLOW}[5/6] Extracting binaries...${NC}"

# Run container to export files
docker run \
    --rm \
    --platform "$PLATFORM" \
    -v "$OUTPUT_DIR:/export" \
    "$IMAGE_NAME:$IMAGE_TAG"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Binaries extracted${NC}"
else
    echo -e "${RED}✗ Failed to extract binaries${NC}"
    exit 1
fi

echo ""

# ============================================================
# Verify output
# ============================================================
echo -e "${YELLOW}[6/6] Verifying build output...${NC}"

# Check tarball
if [ -f "$OUTPUT_DIR/svxlink-h3-armhf.tar.gz" ]; then
    SIZE=$(du -h "$OUTPUT_DIR/svxlink-h3-armhf.tar.gz" | cut -f1)
    echo -e "${GREEN}✓ Binary tarball: svxlink-h3-armhf.tar.gz ($SIZE)${NC}"
else
    echo -e "${RED}✗ Binary tarball not found${NC}"
    exit 1
fi

# Check build log
if [ -f "$OUTPUT_DIR/build.log" ]; then
    echo -e "${GREEN}✓ Build log: build.log${NC}"

    # Check for NEON optimization
    echo ""
    echo -e "${BLUE}Checking NEON optimization...${NC}"
    if grep -q "STRONG NEON" "$OUTPUT_DIR/build.log"; then
        echo -e "${GREEN}✓ STRONG NEON optimization detected${NC}"
    elif grep -q "MODERATE NEON" "$OUTPUT_DIR/build.log"; then
        echo -e "${YELLOW}⚠ MODERATE NEON usage${NC}"
    elif grep -q "NO NEON" "$OUTPUT_DIR/build.log"; then
        echo -e "${RED}✗ NO NEON optimization (build may be incorrect)${NC}"
    else
        echo -e "${YELLOW}⚠ Could not verify NEON optimization${NC}"
    fi
fi

echo ""

# ============================================================
# Extract and inspect tarball (optional)
# ============================================================
echo -e "${BLUE}Extracting tarball for inspection...${NC}"
cd "$OUTPUT_DIR"
tar xzf svxlink-h3-armhf.tar.gz

if [ -f "opt/rolink/bin/svxlink" ]; then
    echo -e "${GREEN}✓ Binary extracted: opt/rolink/bin/svxlink${NC}"

    # Show file info
    echo ""
    echo -e "${BLUE}Binary information:${NC}"
    file opt/rolink/bin/svxlink | sed 's/^/  /'

    echo ""
    echo -e "${BLUE}Binary size:${NC}"
    ls -lh opt/rolink/bin/svxlink | awk '{print "  " $5 " - " $9}'
fi

echo ""

# ============================================================
# SUCCESS
# ============================================================
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           BUILD SUCCESSFUL!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}Build artifacts in: $OUTPUT_DIR${NC}"
echo ""
echo -e "${YELLOW}Files created:${NC}"
echo -e "  📦 svxlink-h3-armhf.tar.gz - Binary tarball"
echo -e "  📄 build.log - Compilation log"
echo -e "  📂 opt/rolink/ - Extracted files"
echo ""

echo -e "${BLUE}Optimizations applied:${NC}"
echo -e "  - ARM Cortex-A7 tuning (-mtune=cortex-a7)"
echo -e "  - NEON SIMD vectorization (-mfpu=neon-vfpv4)"
echo -e "  - Hardware floating point (-mfloat-abi=hard)"
echo -e "  - Maximum optimization (-O3 -ftree-vectorize)"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Transfer to Orange Pi:"
echo -e "     ${BLUE}scp build-output/svxlink-h3-armhf.tar.gz pi@OPI_IP:/tmp/${NC}"
echo ""
echo -e "  2. Extract on Orange Pi:"
echo -e "     ${BLUE}cd /tmp${NC}"
echo -e "     ${BLUE}tar xzf svxlink-h3-armhf.tar.gz${NC}"
echo -e "     ${BLUE}sudo cp -r opt/rolink /opt/${NC}"
echo ""
echo -e "  3. Create symlinks (optional):"
echo -e "     ${BLUE}sudo ln -s /opt/rolink/bin/svxlink /usr/local/bin/svxlink${NC}"
echo ""
echo -e "  4. Configure:"
echo -e "     ${BLUE}sudo nano /opt/rolink/conf/svxlink.conf${NC}"
echo ""
echo -e "  5. Test:"
echo -e "     ${BLUE}/opt/rolink/bin/svxlink --help${NC}"
echo ""

echo -e "${GREEN}Build completed successfully!${NC}"
echo ""
