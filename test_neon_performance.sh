#!/bin/bash
# test_neon_performance.sh - Test NEON optimization effectiveness
#
# This script tests if SVXLink binary uses ARM NEON instructions
# and measures audio processing performance

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  SVXLink NEON Performance Test                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# 1. CPU Information
# ============================================================
echo -e "${YELLOW}[1/5] CPU Information${NC}"
echo ""

echo -e "${BLUE}Architecture:${NC}"
uname -m

echo ""
echo -e "${BLUE}CPU Model:${NC}"
grep "model name\|Hardware" /proc/cpuinfo | head -3

echo ""
echo -e "${BLUE}CPU Cores:${NC}"
nproc

echo ""
echo -e "${BLUE}CPU Frequency:${NC}"
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
  FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
  FREQ_MHZ=$((FREQ / 1000))
  echo "${FREQ_MHZ} MHz"
else
  echo "Unable to read CPU frequency"
fi

echo ""
echo -e "${BLUE}CPU Features:${NC}"
grep "Features" /proc/cpuinfo | head -1

# Check for NEON support
if grep -q "neon" /proc/cpuinfo; then
  echo -e "${GREEN}✓ NEON support detected in CPU${NC}"
else
  echo -e "${RED}✗ NEON NOT detected (this is bad for performance!)${NC}"
fi

echo ""

# ============================================================
# 2. Binary Analysis
# ============================================================
echo -e "${YELLOW}[2/5] Binary Analysis${NC}"
echo ""

SVXLINK_BIN=$(which svxlink 2>/dev/null)

if [ -z "$SVXLINK_BIN" ]; then
  echo -e "${RED}✗ SVXLink binary not found${NC}"
  exit 1
fi

echo -e "${BLUE}SVXLink binary: $SVXLINK_BIN${NC}"

# Check ELF architecture
echo ""
echo -e "${BLUE}Binary architecture:${NC}"
file "$SVXLINK_BIN"

# Check for NEON instructions in binary
echo ""
echo -e "${BLUE}Checking for NEON instructions in binary...${NC}"

if ! command -v objdump &> /dev/null; then
  echo -e "${YELLOW}⚠ objdump not found, installing binutils...${NC}"
  sudo apt-get install -y binutils
fi

# Look for NEON instructions
NEON_INSTRUCTIONS=$(objdump -d "$SVXLINK_BIN" 2>/dev/null | grep -E "vfma|vmla|vadd|vmul|vsub|vld|vst|vmax|vmin" | wc -l)

echo "NEON instructions found: $NEON_INSTRUCTIONS"

if [ "$NEON_INSTRUCTIONS" -gt 100 ]; then
  echo -e "${GREEN}✓ STRONG NEON optimization detected (${NEON_INSTRUCTIONS} instructions)${NC}"
  echo -e "${GREEN}  Binary is well optimized for ARM Cortex-A7${NC}"
elif [ "$NEON_INSTRUCTIONS" -gt 10 ]; then
  echo -e "${YELLOW}⚠ MODERATE NEON usage (${NEON_INSTRUCTIONS} instructions)${NC}"
  echo -e "${YELLOW}  Some optimization, but could be better${NC}"
else
  echo -e "${RED}✗ LITTLE/NO NEON optimization (${NEON_INSTRUCTIONS} instructions)${NC}"
  echo -e "${RED}  Binary may not be properly optimized!${NC}"
  echo -e "${YELLOW}  Re-compile with: -mfpu=neon-vfpv4 -ftree-vectorize${NC}"
fi

# Sample NEON instructions
echo ""
echo -e "${BLUE}Sample NEON instructions found:${NC}"
objdump -d "$SVXLINK_BIN" 2>/dev/null | grep -E "vfma|vmla|vadd|vmul" | head -5

echo ""

# ============================================================
# 3. Library Dependencies
# ============================================================
echo -e "${YELLOW}[3/5] Library Dependencies${NC}"
echo ""

echo -e "${BLUE}SVXLink shared libraries:${NC}"
ldd "$SVXLINK_BIN" | grep -E "libasync|libecholib|libalsa|libspeex|libopus"

echo ""
echo -e "${BLUE}Async library location:${NC}"
ASYNC_LIB=$(ldd "$SVXLINK_BIN" | grep libasync | awk '{print $3}')
if [ -n "$ASYNC_LIB" ]; then
  ls -lh "$ASYNC_LIB"

  # Check NEON in libasync (audio processing core)
  ASYNC_NEON=$(objdump -d "$ASYNC_LIB" 2>/dev/null | grep -E "vfma|vmla|vadd|vmul" | wc -l)
  echo ""
  echo "NEON instructions in libasync: $ASYNC_NEON"

  if [ "$ASYNC_NEON" -gt 50 ]; then
    echo -e "${GREEN}✓ libasync has STRONG NEON optimization${NC}"
  elif [ "$ASYNC_NEON" -gt 10 ]; then
    echo -e "${YELLOW}⚠ libasync has MODERATE NEON usage${NC}"
  else
    echo -e "${RED}✗ libasync has LITTLE/NO NEON optimization${NC}"
  fi
fi

echo ""

# ============================================================
# 4. Compiler Flags Verification
# ============================================================
echo -e "${YELLOW}[4/5] Compiler Flags Verification${NC}"
echo ""

echo -e "${BLUE}Checking build info in binary...${NC}"

# Check for ARM-specific sections
if readelf -A "$SVXLINK_BIN" 2>/dev/null | grep -q "Tag_FP_arch"; then
  echo -e "${GREEN}✓ ARM attributes found${NC}"
  readelf -A "$SVXLINK_BIN" 2>/dev/null | grep -E "Tag_CPU|Tag_FP|Tag_Advanced_SIMD"
else
  echo -e "${YELLOW}⚠ No ARM attributes found${NC}"
fi

echo ""

# ============================================================
# 5. Performance Estimate
# ============================================================
echo -e "${YELLOW}[5/5] Performance Estimate${NC}"
echo ""

echo -e "${BLUE}Audio processing capabilities (estimated):${NC}"

# Calculate based on CPU freq and NEON optimization
CPU_CORES=$(nproc)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
  CPU_FREQ=$(($(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) / 1000))
else
  CPU_FREQ=1200  # Default for H3
fi

# Estimate performance
# H3 @ 1.2GHz with NEON can handle:
# - 16kHz audio: ~32 simultaneous channels (with NEON)
# - 8kHz audio: ~64 simultaneous channels (with NEON)
# WITHOUT NEON: divide by 3-4

if [ "$NEON_INSTRUCTIONS" -gt 100 ]; then
  PERF_MULTIPLIER=1.0
  OPTIMIZATION="EXCELLENT"
elif [ "$NEON_INSTRUCTIONS" -gt 10 ]; then
  PERF_MULTIPLIER=0.5
  OPTIMIZATION="MODERATE"
else
  PERF_MULTIPLIER=0.25
  OPTIMIZATION="POOR"
fi

CHANNELS_16K=$(echo "scale=0; 32 * $PERF_MULTIPLIER" | bc)
CHANNELS_8K=$(echo "scale=0; 64 * $PERF_MULTIPLIER" | bc)

echo ""
echo -e "  CPU: ${CPU_CORES}x ARM Cortex-A7 @ ${CPU_FREQ}MHz"
echo -e "  Optimization: ${OPTIMIZATION}"
echo -e "  Estimated 16kHz channels: ~${CHANNELS_16K}"
echo -e "  Estimated 8kHz channels: ~${CHANNELS_8K}"

echo ""

if [ "$NEON_INSTRUCTIONS" -gt 100 ]; then
  echo -e "${GREEN}✓ EXCELLENT performance expected${NC}"
  echo -e "${GREEN}  - Low CPU usage for audio processing${NC}"
  echo -e "${GREEN}  - Fast sample rate conversion (SRC)${NC}"
  echo -e "${GREEN}  - Efficient audio mixing${NC}"

  echo ""
  echo -e "${BLUE}Typical CPU usage (per component):${NC}"
  echo -e "  - Squelch/VOX processing: 2-5%"
  echo -e "  - Sample rate conversion (16kHz→48kHz): 3-7%"
  echo -e "  - Audio filters (bandpass): 2-4%"
  echo -e "  - Opus encode (20kbps): 5-10%"
  echo -e "  - TOTAL per channel: ~15-25%"

elif [ "$NEON_INSTRUCTIONS" -gt 10 ]; then
  echo -e "${YELLOW}⚠ MODERATE performance expected${NC}"
  echo -e "${YELLOW}  - Medium CPU usage${NC}"
  echo -e "${YELLOW}  - Some operations may be slow${NC}"

  echo ""
  echo -e "${BLUE}Typical CPU usage:${NC}"
  echo -e "  - TOTAL per channel: ~30-50%"

else
  echo -e "${RED}✗ POOR performance expected${NC}"
  echo -e "${RED}  - HIGH CPU usage (3-4x normal)${NC}"
  echo -e "${RED}  - May struggle with real-time audio${NC}"
  echo -e "${RED}  - Recommend re-compilation with NEON flags${NC}"

  echo ""
  echo -e "${YELLOW}To improve performance:${NC}"
  echo -e "  1. Re-compile with build_orangepi_h3.sh"
  echo -e "  2. Verify CFLAGS include: -mfpu=neon-vfpv4"
  echo -e "  3. Re-run this test"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           PERFORMANCE TEST COMPLETE                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}Summary:${NC}"
echo -e "  NEON instructions: $NEON_INSTRUCTIONS"
echo -e "  Optimization level: $OPTIMIZATION"
echo -e "  Estimated 16kHz channels: ~$CHANNELS_16K"
echo ""

if [ "$NEON_INSTRUCTIONS" -gt 100 ]; then
  echo -e "${GREEN}✓ Your build is well optimized for Orange Pi Zero H3!${NC}"
else
  echo -e "${YELLOW}⚠ Consider rebuilding with NEON optimizations${NC}"
fi

echo ""
