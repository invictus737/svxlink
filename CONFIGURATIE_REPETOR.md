# CONFIGURAȚIA REPETOR - MMDVM + GM340 + SVXLINK

## Arhitectura ta specifică

### Hardware Setup
```
┌─────────────────────┐
│  Motorola GM340 RX  │  (Receiver - primește de la stații)
│  (Stație analogă)   │
└──────────┬──────────┘
           │ Audio analog (discriminator output)
           │
           ▼
┌─────────────────────┐
│   Placa MMDVM       │
│  (Mod ANALOG activ) │
│                     │
│  - ADC: RX audio    │
│  - DAC: TX audio    │
│  - PTT control      │
└──────────┬──────────┘
           │ Audio analog (line output)
           │
           ▼
┌─────────────────────┐
│  Motorola GM340 TX  │  (Transmitter - transmite către stații)
│  (Stație analogă)   │
└─────────────────────┘
```

### Software Stack
```
┌─────────────────────────────────────────────────────────┐
│                    SVXLink (Client)                     │
│                  UsrpLogic Module                       │
│  - Conectat la reflector extern                        │
│  - Primește/trimite audio de la/către utilizatori      │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ UDP USRP Protocol
                     │ (8kHz PCM audio + metadata)
                     │ Port 41234 TX, 41233 RX
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   Analog_Bridge                         │
│  - Convertește între USRP și MMDVM                     │
│  - Nu face transcoding AMBE (mod analog)               │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ Serial/USB communication
                     │ (comenzi + audio PCM)
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                    MMDVMHost                            │
│                  (Analog Mode)                          │
│  - Controlează placa MMDVM                             │
│  - Gestionează PTT pentru GM340                        │
│  - Audio pass-through (analog)                         │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ Serial/USB (către placa MMDVM)
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   Placa MMDVM                           │
│  - ADC: digitalizează audio de la GM340 RX             │
│  - DAC: convertește digital → analog pentru GM340 TX   │
│  - GPIO: controlează PTT                               │
└─────────────────────────────────────────────────────────┘
```

---

## Flow Audio - RX (Recepție de la stații locale)

```
1. Stație locală transmite
   ↓
2. GM340 RX primește semnalul RF
   ↓ Audio analog (discriminator output)
3. Placa MMDVM - ADC convertește analog → digital
   ↓ PCM digital (8kHz, 16-bit)
4. MMDVMHost (mod analog) - pass-through
   ↓ Serial/USB
5. Analog_Bridge - încapsulează în protocol USRP
   ↓ UDP USRP_TYPE_VOICE frames (160 samples/20ms)
6. SVXLink UsrpLogic - procesare audio
   ├─ AudioDecoder (S16)
   ├─ AudioInterpolator (8kHz → 16kHz)
   ├─ AudioFilter (FILTER_FROM_USRP)
   ├─ AudioCompressor (NET_LIMITER_THRESH)
   └─ AudioClipper
   ↓ Audio procesat 16kHz
7. SVXLink Logic Core - înregistrează în reflector
   ↓
8. Reflector extern - distribuie către toți clienții
```

---

## Flow Audio - TX (Transmisie către stații locale)

```
1. Utilizator remote vorbește în reflector
   ↓
2. Reflector extern - trimite audio către SVXLink client
   ↓ Opus/Speex/Raw (depinde de reflector)
3. SVXLink Logic Core - decodifică
   ↓ PCM 16kHz
4. SVXLink UsrpLogic - procesare TX
   ├─ AudioFilter (FILTER_TO_USRP)
   ├─ AudioDecimator (16kHz → 8kHz)
   ├─ AudioCompressor (LOCAL_LIMITER_THRESH)
   ├─ AudioClipper
   └─ AudioEncoder (S16)
   ↓ UDP USRP_TYPE_VOICE frames
5. Analog_Bridge - extrage audio PCM
   ↓ Serial/USB (8kHz PCM)
6. MMDVMHost (mod analog) - controlează PTT
   ├─ Activează PTT pentru GM340 TX
   └─ Trimite audio către MMDVM
   ↓
7. Placa MMDVM - DAC convertește digital → analog
   ↓ Audio analog (line level)
8. GM340 TX - modulează și transmite RF
   ↓
9. Stații locale primesc transmisia
```

---

## Configurare Necesară

### 1. MMDVMHost Configuration (`MMDVM.ini`)

```ini
[General]
Callsign=YourCall
Timeout=180
Duplex=1                    # Repeater mode (RX și TX separate)
ModeHang=10
RFModeHang=10
NetModeHang=10

[Info]
TXFrequency=433450000       # Frecvența GM340 TX
RXFrequency=433450000       # Frecvența GM340 RX (sau offset)
Power=1
Latitude=0.0
Longitude=0.0
Height=0
Location=Your Location
Description=MMDVM Analog Repeater

[Modem]
Port=/dev/ttyACM0           # Portul serial al MMDVM
Protocol=uart
TXInvert=0
RXInvert=0
PTTInvert=0
TXDelay=100
RXOffset=0
TXOffset=0
DMRDelay=0
RXLevel=50                  # Nivel RX (ajustează pentru GM340)
TXLevel=50                  # Nivel TX (ajustează pentru GM340)
RXDCOffset=0
TXDCOffset=0

# ⭐ IMPORTANT: Activează DOAR modul FM (analog)
[FM Network]
Enable=1                    # Activează networking pentru FM
LocalAddress=127.0.0.1
LocalPort=32768             # Port pentru Analog_Bridge
GatewayAddress=127.0.0.1
GatewayPort=31000           # Port către Analog_Bridge
ModeHang=10
CallsignAtStart=1
CallsignAtEnd=1
CallsignAtLatch=1
RFAck=K
NetAck=N
Timeout=180
TimeoutLevel=50
CTCSSFrequency=0.0
CTCSSHighThreshold=30
CTCSSLowThreshold=20
CTCSSLevel=2
NoiseSquelch=10
SquelchHighThreshold=30
SquelchLowThreshold=20
RFAudioBoost=1
MaxDevLevel=90

# ❌ Dezactivează modurile digitale
[DMR]
Enable=0

[D-Star]
Enable=0

[System Fusion]
Enable=0

[P25]
Enable=0

[NXDN]
Enable=0
```

### 2. Analog_Bridge Configuration (`Analog_Bridge.ini`)

```ini
[GENERAL]
decoderFallBack = true
useEmulator = false          # Nu folosim AMBE (mod analog)
useExternalDV3000 = false
useExternalMD380 = false

[USRP]
address = 127.0.0.1
txPort = 41234               # Port TX către SVXLink
rxPort = 41233               # Port RX de la SVXLink
usrpAudioPort = 32768        # Comunicare cu MMDVMHost FM Network

[MMDVM]
address = 127.0.0.1
rxPort = 32768               # Primește de la MMDVMHost
txPort = 31000               # Trimite către MMDVMHost

[AUDIO]
# Audio din SVXLink → MMDVM
to_mmdvm_gain = 1.0          # Ajustează după nevoie
to_mmdvm_shape = AUDIO_USE_AGC

# Audio din MMDVM → SVXLink
to_usrp_gain = 1.0           # Ajustează după nevoie
to_usrp_shape = AUDIO_USE_GAIN

[INFORMATION]
mode = FM                    # ⭐ MOD ANALOG
subscriber = YourCall
latitude = 0.0
longitude = 0.0
```

### 3. SVXLink Configuration (`svxlink.conf`)

```ini
[GLOBAL]
MODULE_PATH=/usr/lib/svxlink
LOGICS=UsrpLogic
CFG_DIR=/etc/svxlink/svxlink.d
TIMESTAMP_FORMAT="%c"
CARD_SAMPLE_RATE=16000
CARD_CHANNELS=1

[UsrpLogic]
TYPE=Usrp
CALLSIGN=YourCall           # Max 6 caractere

# ⭐ Conectare la Analog_Bridge
USRP_HOST=127.0.0.1
USRP_TX_PORT=41234          # Trimite audio către Analog_Bridge
USRP_RX_PORT=41233          # Primește audio de la Analog_Bridge

# Pentru mod analog, aceste setări nu sunt folosite (DMR specific)
DMRID=0
RPTID=0
DEFAULT_TG=0
DEFAULT_CC=1
DEFAULT_TS=1

# ⭐ Procesare audio TX (către MMDVM)
PREAMP=0                    # Ajustează gain TX (-20 la +20 dB)
FILTER_TO_USRP=BpBu1/300-3000  # Bandpass 300Hz-3kHz (voce)
LOCAL_LIMITER_THRESH=-6.0   # Limitare compresie TX

# ⭐ Procesare audio RX (de la MMDVM)
NET_PREAMP=0                # Ajustează gain RX (-20 la +20 dB)
FILTER_FROM_USRP=LpBu4/3000 # Lowpass 3kHz (anti-aliasing)
NET_LIMITER_THRESH=-6.0     # Limitare compresie RX

# ⭐ CRITICAL: Nu folosi jitter buffer pentru mod analog
# JITTER_BUFFER_DELAY=0     # Comentat sau 0 pentru latență minimă

# Event handler pentru logică
EVENT_HANDLER=/usr/share/svxlink/events.tcl

# Debug (0=ERROR, 1=WARN, 2=INFO, 3=DEBUG)
DEBUG=2

# ⭐ Conectare la Reflector Extern
[ReflectorLogic]
TYPE=Reflector              # Tip reflector (Simplex/Repeater/Reflector)
CALLSIGN=YourCall
HOST=reflector.example.com  # Adresa reflectorului extern
PORT=5300                   # Portul reflectorului
AUTH_KEY=YourAuthKey        # Cheie de autentificare (dacă e necesar)
CODEC=OPUS                  # Codec pentru reflector (OPUS/SPEEX/GSM)

# Link între UsrpLogic și ReflectorLogic
CONNECT_LOGICS=UsrpLogic:9:ReflectorLogic
```

---

## Secvența de Pornire

```bash
# 1. Pornește MMDVMHost (controlează placa MMDVM)
sudo systemctl start mmdvmhost

# 2. Pornește Analog_Bridge (broker între MMDVM și SVXLink)
sudo systemctl start analog_bridge

# 3. Pornește SVXLink (client reflector)
sudo systemctl start svxlink
```

---

## Verificare Funcționalitate

### Test 1: Audio RX (stație locală → reflector)

1. Transmite pe frecvența GM340 RX
2. Verifică în log-urile SVXLink:
   ```bash
   tail -f /var/log/svxlink.log
   ```
   Ar trebui să vezi:
   ```
   UsrpLogic: incoming packet from 127.0.0.1, len=352
   UsrpLogic: handleVoiceStream
   Logic: Talker start
   ```

3. Verifică în Analog_Bridge:
   ```bash
   tail -f /var/log/analog_bridge.log
   ```
   Ar trebui să vezi trafic USRP:
   ```
   USRP RX: VOICE frame, seq=1234
   MMDVM TX: audio samples
   ```

4. Verifică în MMDVMHost:
   ```bash
   tail -f /var/log/mmdvm.log
   ```
   Ar trebui să vezi:
   ```
   M: 2025-10-26 FM network transmission
   ```

### Test 2: Audio TX (reflector → stație locală)

1. Alt utilizator vorbește în reflector
2. Verifică că GM340 TX transmite (LED PTT aprins)
3. Verifică audio pe receptor local

### Test 3: Latență End-to-End

Latența totală ar trebui să fie:
```
RX Audio:
  ADC MMDVM: ~5ms
  MMDVMHost: ~2ms
  Analog_Bridge: ~2ms
  SVXLink: ~5ms (fără jitter buffer)
  Reflector: ~50-100ms (internet)
  ─────────────────────────
  TOTAL RX: ~64-114ms

TX Audio:
  Reflector: ~50-100ms
  SVXLink: ~5ms
  Analog_Bridge: ~2ms
  MMDVMHost: ~2ms
  DAC MMDVM: ~5ms
  ─────────────────────────
  TOTAL TX: ~64-114ms

ROUND-TRIP: ~128-228ms
```

---

## Troubleshooting

### Problema: Nu primește audio de la MMDVM

**Verificări:**
```bash
# 1. Verifică că Analog_Bridge ascultă pe portul corect
sudo netstat -ulpn | grep 41233

# 2. Verifică nivelul audio RX în MMDVM
# Ajustează RXLevel în MMDVM.ini (valori 1-100)

# 3. Verifică gain în SVXLink
# Ajustează NET_PREAMP în svxlink.conf

# 4. Test direct USRP protocol
sudo tcpdump -i lo -X port 41233
# Ar trebui să vezi pachete UDP cu "USRP" în header
```

### Problema: Nu transmite către MMDVM

**Verificări:**
```bash
# 1. Verifică că SVXLink trimite pachete
sudo tcpdump -i lo -X port 41234

# 2. Verifică PTT control în MMDVM
# GPIO pentru PTT trebuie configurat corect în hardware

# 3. Verifică gain TX
# Ajustează PREAMP în svxlink.conf

# 4. Verifică TXLevel în MMDVM.ini
```

### Problema: Audio distorsionat

**Ajustări:**
```ini
# În svxlink.conf

# Dacă audio TX e prea tare:
PREAMP=-6                   # Reduce gain

# Dacă audio TX e prea slab:
PREAMP=+6                   # Crește gain

# Dacă audio e clipping:
LOCAL_LIMITER_THRESH=-10.0  # Limitare mai agresivă

# Dacă audio RX e prea tare:
NET_PREAMP=-6

# Dacă audio RX e prea slab:
NET_PREAMP=+6
```

---

## Optimizări Performance

### 1. Reduce Latency

```ini
# În svxlink.conf
# ❌ NU folosi jitter buffer pentru mod analog
# JITTER_BUFFER_DELAY=0

# În MMDVM.ini
# Reduce TXDelay la minim funcțional
TXDelay=50                  # În loc de 100

# Reduce ModeHang
ModeHang=5                  # În loc de 10
```

### 2. Îmbunătățește Calitatea Audio

```ini
# În svxlink.conf

# Filtre optimizate pentru voce
FILTER_TO_USRP=BpBu2/300-3000      # Bandpass de ordin 2
FILTER_FROM_USRP=BpBu2/300-3000    # Simetric

# Compresie blândă
LOCAL_LIMITER_THRESH=-8.0
NET_LIMITER_THRESH=-8.0
```

### 3. Monitoring în Timp Real

```bash
# Script de monitoring
watch -n 1 '
echo "=== MMDVMHost ==="
sudo systemctl status mmdvmhost | grep Active
echo ""
echo "=== Analog_Bridge ==="
sudo systemctl status analog_bridge | grep Active
echo ""
echo "=== SVXLink ==="
sudo systemctl status svxlink | grep Active
echo ""
echo "=== UDP Traffic ==="
sudo netstat -s | grep "packets received"
'
```

---

## Concluzie

Configurația ta este:
- **Hardware:** GM340 RX + MMDVM + GM340 TX
- **Software:** MMDVMHost (analog) → Analog_Bridge → SVXLink → Reflector extern
- **Protocol:** USRP pentru comunicare între componente
- **Sample rate:** 8kHz (USRP protocol), 16kHz (SVXLink intern)
- **Latență:** ~64-114ms per direcție (acceptabil pentru repetor)

**Flux complet:**
```
Stație locală → GM340 RX → MMDVM ADC → MMDVMHost →
Analog_Bridge → SVXLink → Reflector →
SVXLink → Analog_Bridge → MMDVMHost → MMDVM DAC →
GM340 TX → Stații locale
```
