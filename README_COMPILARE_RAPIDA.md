# COMPILARE RAPIDĂ SVXLINK PE ORANGE PI ZERO (H3)

## TL;DR - Quick Start

### Pe macOS (Local):

```bash
cd /private/tmp/svxlink

# Transfer fișiere către Orange Pi
scp build_orangepi_h3.sh pi@ORANGE_PI_IP:/home/pi/
scp test_neon_performance.sh pi@ORANGE_PI_IP:/home/pi/

# SAU transfer întreg repository
rsync -avz --progress /private/tmp/svxlink/ pi@ORANGE_PI_IP:/home/pi/svxlink/
```

### Pe Orange Pi (Remote):

```bash
# Conectează-te via SSH
ssh pi@ORANGE_PI_IP

# Rulează build (durează 20-30 min)
cd ~
chmod +x build_orangepi_h3.sh
./build_orangepi_h3.sh

# Test NEON optimization
chmod +x test_neon_performance.sh
./test_neon_performance.sh

# Start SVXLink
sudo systemctl start svxlink
sudo journalctl -u svxlink -f
```

---

## Fișiere Create

| Fișier | Descriere |
|--------|-----------|
| `build_orangepi_h3.sh` | ⭐ Script automat de compilare cu optimizări NEON |
| `test_neon_performance.sh` | Test verificare optimizări NEON |
| `COMPILARE_ORANGE_PI_H3.md` | 📖 Documentație completă (metodă manuală + troubleshooting) |
| `PROCEDURA_CALIBRARE_OPTIMA_VAD.md` | 📖 Procedură calibrare VAD/anti-kerchunk |
| `CONFIGURATIE_REPETOR.md` | 📖 Setup hardware GM340 + MMDVM |
| `CONFIGURATIE_SIMPLA_ANALOG.md` | 📖 Explicație analog vs DMR |
| `VOICE_ACTIVITY_DETECTION_ANTI_KERCHUNK.md` | 📖 VAD implementation guide |
| `SVXLINK_ARCHITECTURE.md` | 📖 Arhitectură SVXLink |

---

## Transfer Rapid - 3 Metode

### Metodă 1: SCP (Simple Copy)

```bash
# Transfer script-uri individuale
scp build_orangepi_h3.sh pi@192.168.1.100:/home/pi/
scp test_neon_performance.sh pi@192.168.1.100:/home/pi/
```

### Metodă 2: Rsync (Entire Repository)

```bash
# Sincronizează tot folderul (excluzând build artifacts)
rsync -avz --progress \
  --exclude='.git' \
  --exclude='src/build*' \
  --exclude='*.o' \
  --exclude='*.so' \
  /private/tmp/svxlink/ pi@192.168.1.100:/home/pi/svxlink/
```

### Metodă 3: Git (Dacă ai repository remote)

```bash
# Pe Orange Pi
ssh pi@192.168.1.100

cd ~
git clone https://github.com/sm0svx/svxlink.git
cd svxlink
git checkout master  # sau branch-ul tău

# Transfer doar script-urile custom de pe macOS
# (pe macOS)
scp build_orangepi_h3.sh test_neon_performance.sh pi@192.168.1.100:/home/pi/svxlink/
```

---

## Verificare Pre-Build

### Pe Orange Pi - Înainte de Build

```bash
# Verifică arhitectura (ar trebui să fie armv7l)
uname -m

# Verifică CPU (ar trebui Allwinner H3)
cat /proc/cpuinfo | grep Hardware

# Verifică NEON support în CPU
grep "neon" /proc/cpuinfo

# Verifică spațiu disk (minim 2GB free)
df -h

# Verifică RAM (minim 512MB)
free -h
```

**Expected output:**
```
uname -m: armv7l
Hardware: Allwinner sun8i Family
Features: ... neon ...
Disk free: >2GB
RAM: 512MB (Orange Pi Zero)
```

---

## Build Process - Ce Face Script-ul?

```
[1/7] Verificare platform (ARM, H3)
      ├─ Detectează arhitectură: armv7l
      ├─ Verifică Allwinner H3
      └─ Numără CPU cores: 4

[2/7] Instalare dependințe
      ├─ build-essential, cmake, git
      ├─ libsigc++, libgsm, libpopt
      ├─ libasound2, libopus, libspeex
      └─ tcl, libcurl

[3/7] Pregătire build environment
      ├─ Source directory: ~/svxlink
      └─ Build directory: ~/svxlink/src/build-orangepi-h3

[4/7] Configurare CMake
      ├─ CFLAGS: -march=armv7-a -mtune=cortex-a7
      ├─        -mfpu=neon-vfpv4  ⭐ CRITICAL
      ├─        -O3 -ftree-vectorize -ffast-math
      └─ CMake: Release build

[5/7] Compilare (15-30 min)
      ├─ Parallel jobs: 4 (toate core-urile)
      └─ Progress: visible în terminal

[6/7] Instalare
      ├─ Binare → /usr/bin/svxlink
      ├─ Libraries → /usr/lib/
      ├─ Config → /etc/svxlink/
      └─ Systemd → /lib/systemd/system/

[7/7] Verificare
      ├─ svxlink --version
      ├─ Check libraries (ldd)
      └─ Check NEON instructions (objdump)
```

---

## Expected Build Output

### Success Message

```
╔════════════════════════════════════════════════════════╗
║           BUILD SUCCESSFUL!                            ║
╚════════════════════════════════════════════════════════╝

Build optimizations applied:
  - ARM Cortex-A7 tuning (-mtune=cortex-a7)
  - NEON SIMD vectorization (-mfpu=neon-vfpv4)
  - Hardware floating point (-mfloat-abi=hard)
  - Maximum optimization (-O3 -ftree-vectorize)

Next steps:
  1. Configure SVXLink: sudo nano /etc/svxlink/svxlink.conf
  2. Start service: sudo systemctl start svxlink
  3. Check status: sudo systemctl status svxlink
  4. View logs: sudo journalctl -u svxlink -f
```

### Performance Test Output

```
[1/5] CPU Information
✓ Platform verified: armv7l
✓ Allwinner H3 detected
✓ CPU cores: 4
✓ NEON support detected in CPU

[2/5] Binary Analysis
NEON instructions found: 523
✓ STRONG NEON optimization detected (523 instructions)
  Binary is well optimized for ARM Cortex-A7

[5/5] Performance Estimate
  CPU: 4x ARM Cortex-A7 @ 1200MHz
  Optimization: EXCELLENT
  Estimated 16kHz channels: ~32
  Estimated 8kHz channels: ~64

✓ EXCELLENT performance expected
  - Low CPU usage for audio processing
  - Fast sample rate conversion (SRC)
  - Efficient audio mixing

Typical CPU usage (per component):
  - Squelch/VOX processing: 2-5%
  - Sample rate conversion (16kHz→48kHz): 3-7%
  - Audio filters (bandpass): 2-4%
  - Opus encode (20kbps): 5-10%
  - TOTAL per channel: ~15-25%
```

---

## Troubleshooting Rapid

### Build Failed - Out of Memory

**Symptom:**
```
g++: fatal error: Killed signal terminated program
```

**Fix:**
```bash
# Add swap
sudo dd if=/dev/zero of=/swapfile bs=1M count=1024
sudo mkswap /swapfile
sudo swapon /swapfile

# Rebuild cu mai puține jobs
cd ~/svxlink/src/build-orangepi-h3
make -j2  # În loc de -j4
```

### No NEON Instructions

**Symptom:**
```
NEON instructions found: 0
✗ LITTLE/NO NEON optimization
```

**Fix:**
```bash
# Verifică CMake cache
cd ~/svxlink/src/build-orangepi-h3
cat CMakeCache.txt | grep CMAKE_C_FLAGS

# Dacă lipsesc flags NEON, șterge cache și rebuilld
rm -rf *
../build_orangepi_h3.sh  # Re-run script
```

### Service Won't Start

**Symptom:**
```
systemctl status svxlink
● svxlink.service - SvxLink Repeater/Simplex Server
   Loaded: loaded
   Active: failed
```

**Fix:**
```bash
# Check logs pentru error exact
sudo journalctl -u svxlink -n 50

# Common issues:
# 1. Config file error → check /etc/svxlink/svxlink.conf
# 2. Audio device missing → check AUDIO_DEV
# 3. Port already in use → check USRP_TX_PORT/RX_PORT
```

---

## Performance Monitoring

### Quick CPU Check

```bash
# CPU usage (real-time)
top -p $(pidof svxlink)

# Expected: 15-25% per channel (cu NEON)
# Warning: >50% per channel (possibil NO NEON)
```

### Quick Temperature Check

```bash
# Temperature
cat /sys/class/thermal/thermal_zone0/temp | awk '{print $1/1000 "°C"}'

# Safe: <60°C
# Warning: 60-70°C
# Critical: >70°C (add heatsink!)
```

### Quick Memory Check

```bash
free -h

# Expected: ~60-80MB used by SVXLink
```

---

## Next Steps După Build

### 1. Transfer Configurația

```bash
# Pe macOS (transfer config calibrat)
scp /private/tmp/svxlink/*.conf pi@ORANGE_PI_IP:/tmp/
scp /private/tmp/svxlink/*.md pi@ORANGE_PI_IP:/home/pi/docs/

# Pe Orange Pi (aplică config)
sudo cp /tmp/*.conf /etc/svxlink/
```

### 2. Configurare MMDVM + Analog_Bridge

Vezi **CONFIGURATIE_REPETOR.md** pentru setup complet:
- MMDVM.ini (FM mode)
- Analog_Bridge.ini
- SVXLink svxlink.conf

### 3. Calibrare VAD

Vezi **PROCEDURA_CALIBRARE_OPTIMA_VAD.md** pentru calibrare pas-cu-pas:
- VOX_THRESH tuning
- SQL_HANGTIME tuning
- Dual squelch (VOX + SIGLEV)
- Teste validare 90%+ accuracy

### 4. Start în Producție

```bash
# Enable auto-start la boot
sudo systemctl enable svxlink

# Start serviciu
sudo systemctl start svxlink

# Monitor logs
sudo journalctl -u svxlink -f
```

---

## Contact și Documentație

**Documentație completă:**
- Build manual: `COMPILARE_ORANGE_PI_H3.md`
- Calibrare VAD: `PROCEDURA_CALIBRARE_OPTIMA_VAD.md`
- Setup repetor: `CONFIGURATIE_REPETOR.md`
- Arhitectură: `SVXLINK_ARCHITECTURE.md`

**Quick reference:**
- Orange Pi specs: ARMv7-A, Cortex-A7, NEON, 1.2GHz quad-core, 512MB RAM
- Build time: 20-30 minutes
- Expected CPU: 15-25% per channel (cu NEON)
- Expected temp: 50-60°C (idle/moderate load)

**Critical pentru performance:**
- ✅ **MUST** compile with NEON (`-mfpu=neon-vfpv4`)
- ✅ **MUST** verify NEON instructions in binary (>100)
- ✅ **RECOMMENDED** use heatsink (temperature management)
- ✅ **RECOMMENDED** use 16kHz sample rate (not 48kHz)

---

**Good luck! 🎯**

Pentru probleme: verifică logs cu `sudo journalctl -u svxlink -f`
