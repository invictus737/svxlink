# CONFIGURAȚIE SIMPLIFICATĂ - REPETOR ANALOG CURAT

## Ce NU ai nevoie

❌ **NU ai nevoie de:**
- **Codec AMBE** (DV3000, md380-emu) - acestea sunt DOAR pentru DMR/P25/NXDN
- **Transcoding digital** - nu convertești între DMR și analog
- **MMDVMHost în mod digital** - folosești doar modul FM (analog)
- **TLV metadata DMR** (DMR ID, Talkgroup, Timeslot, Color Code) - inutile în analog
- **AMBE frame processing** - nu există frame-uri AMBE în analog

## Ce AI nevoie

✅ **Setup minimal pentru audio analog de calitate:**

```
Stații locale (FM analog)
     ↓
GM340 RX → Audio analog (discriminator sau line out)
     ↓
MMDVM (ADC simplu: analog → 8kHz PCM)
     ↓
MMDVMHost (mod FM - pass-through audio)
     ↓
Analog_Bridge (UDP USRP protocol - transport PCM)
     ↓
SVXLink (procesare audio + reflector client)
     ↓
Reflector extern
     ↓
SVXLink
     ↓
Analog_Bridge
     ↓
MMDVMHost (PTT control)
     ↓
MMDVM (DAC simplu: 8kHz PCM → analog)
     ↓
GM340 TX → RF analog către stații locale
```

---

## Calitate Audio: Analog vs DMR

### DMR → Analog (ce NU faci tu)
```
Audio source (analog)
  → AMBE encoder (7.2 kbps vocoder) ⚠️ PIERDERE MARE
  → DMR frames (compression artifacts)
  → AMBE decoder ⚠️ ZGOMOT, ROBOTICĂ
  → Audio analog degradat

Probleme:
- Voce "robotică" caracteristică DMR
- Pierdere de claritate în consoane (s, f, t)
- Artifacts de compresie (glitch-uri)
- Latență mare (encoding + decoding)
- Band-limiting agresiv (codec optimizat pentru 300-3400Hz)
```

### Analog Direct PCM (ce faci tu)
```
Audio source (analog)
  → ADC 8kHz PCM 16-bit (clean)
  → Transport UDP (no compression)
  → DAC 8kHz PCM 16-bit (clean)
  → Audio analog original

Avantaje:
✅ ZERO artefacte de compresie
✅ Voce naturală, fără "robotică"
✅ Latență minimă (~5-10ms per conversie)
✅ Bandwidth complet (50Hz-3400Hz sau mai mult)
✅ Dinamică completă (fără AGC agresiv DMR)
```

---

## Configurație Optimizată pentru Calitate

### 1. MMDVMHost - FM Mode DOAR (`MMDVM.ini`)

```ini
[General]
Callsign=YourCall
Timeout=180
Duplex=1
ModeHang=5                  # Redus pentru răspuns rapid

# ❌ TOATE modurile digitale DEZACTIVATE
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

[POCSAG]
Enable=0

# ✅ DOAR FM (analog) ACTIVAT
[FM Network]
Enable=1
LocalAddress=127.0.0.1
LocalPort=32768
GatewayAddress=127.0.0.1
GatewayPort=31000

# ⭐ Setări pentru CALITATE MAXIMĂ
RFAudioBoost=1.0            # Fără boost artificial (natural)
MaxDevLevel=90              # 90% deviație maximă (previne over-deviation)
CTCSSFrequency=0.0          # Fără CTCSS (dacă nu e necesar)
NoiseSquelch=10             # Squelch doar pe zgomot (nu pe semnal)
SquelchHighThreshold=30     # Threshold pentru squelch
SquelchLowThreshold=20      # Hysteresis squelch
Timeout=180                 # Timeout 3 minute
TimeoutLevel=50             # Nivel beep timeout
CallsignAtStart=1           # Anunță callsign la început
CallsignAtEnd=1             # Anunță callsign la sfârșit
RFAck=K                     # Acknowledge RF cu "K"
NetAck=N                    # Acknowledge net cu "N"

[Modem]
Port=/dev/ttyACM0
Protocol=uart
TXInvert=0
RXInvert=0
PTTInvert=0
TXDelay=50                  # ⭐ Minim pentru latență redusă
RXOffset=0
TXOffset=0
RXLevel=50                  # ⭐ Ajustează pentru GM340 (20-80)
TXLevel=50                  # ⭐ Ajustează pentru GM340 (20-80)
RXDCOffset=0
TXDCOffset=0
RSSIMappingFile=/etc/mmdvm/RSSI.dat
```

### 2. Analog_Bridge - Fără Transcoding (`Analog_Bridge.ini`)

```ini
[GENERAL]
# ⭐ NU folosim codec digital
decoderFallBack = false     # ❌ Nu fallback pe decoder
useEmulator = false         # ❌ Nu emulator AMBE
useExternalDV3000 = false   # ❌ Nu DV3000
useExternalMD380 = false    # ❌ Nu md380-emu
logLevel = 2

[USRP]
address = 127.0.0.1
txPort = 41234              # Către SVXLink
rxPort = 41233              # De la SVXLink
usrpAudioPort = 32768       # Communication cu MMDVMHost

[MMDVM]
address = 127.0.0.1
rxPort = 32768              # De la MMDVMHost FM Network
txPort = 31000              # Către MMDVMHost FM Network

# ⭐ Audio Settings - CALITATE MAXIMĂ
[AUDIO]
# Audio MMDVM → SVXLink (RX path)
to_usrp_gain = 1.0          # Unity gain (fără amplificare artificială)
to_usrp_shape = AUDIO_USE_GAIN  # ⭐ GAIN simplu (NU AGC!)

# Audio SVXLink → MMDVM (TX path)
to_mmdvm_gain = 1.0         # Unity gain
to_mmdvm_shape = AUDIO_USE_GAIN # ⭐ GAIN simplu (NU AGC!)

# ℹ️ AUDIO_USE_AGC = compresie agresivă (sună ciudat)
# ℹ️ AUDIO_USE_GAIN = transparent (recomandabil)

[INFORMATION]
mode = FM                   # ⭐ MOD ANALOG
subscriber = YourCall
latitude = 0.0
longitude = 0.0
description = Analog FM Repeater
```

### 3. SVXLink - Procesare Audio Minimă (`svxlink.conf`)

```ini
[UsrpLogic]
TYPE=Usrp
CALLSIGN=YourCall

# Network
USRP_HOST=127.0.0.1
USRP_TX_PORT=41234
USRP_RX_PORT=41233

# ❌ Parametri DMR (NU sunt folosiți în mod analog)
DMRID=0                     # Ignorat
RPTID=0                     # Ignorat
DEFAULT_TG=0                # Ignorat
DEFAULT_CC=0                # Ignorat
DEFAULT_TS=0                # Ignorat

# ⭐ Audio Processing TX (către MMDVM)
# MINIMĂ procesare pentru CALITATE MAXIMĂ
PREAMP=0                    # Fără gain artificial
FILTER_TO_USRP=BpBu1/300-3400  # Bandpass voce standard (telefonie)
LOCAL_LIMITER_THRESH=-3.0   # Limitare blândă (previne doar clipping sever)

# ⭐ Audio Processing RX (de la MMDVM)
NET_PREAMP=0                # Fără gain artificial
FILTER_FROM_USRP=BpBu1/300-3400  # Simetric cu TX
NET_LIMITER_THRESH=-3.0     # Limitare blândă

# ⭐ FĂRĂ jitter buffer (latență minimă)
# JITTER_BUFFER_DELAY=0     # Comentat = dezactivat

# Event handler
EVENT_HANDLER=/usr/share/svxlink/events.tcl

# Debug
DEBUG=1                     # Warnings + Errors
```

---

## Comparație Calitate Audio

### DMR → Analog (ce NU faci)
| Parameter | Valoare | Impact |
|-----------|---------|--------|
| Sample rate | 8 kHz | Standard voce |
| Codec | AMBE+2 (7.2 kbps) | ⚠️ Compresie cu pierderi |
| Bitrate | 7200 bps | Foarte comprimat |
| Bandwidth | 300-3400 Hz | Band-limited agresiv |
| Latență | ~40-60ms | Encoding + decoding |
| Claritate | ★★☆☆☆ | Voce "robotică" |
| Naturalețe | ★☆☆☆☆ | Artifacts audibile |

### Analog Direct PCM (ce faci tu)
| Parameter | Valoare | Impact |
|-----------|---------|--------|
| Sample rate | 8 kHz | Standard voce |
| Codec | NONE (raw PCM) | ✅ Fără compresie |
| Bitrate | 128000 bps | ✅ Uncompressed |
| Bandwidth | 50-3400 Hz (sau mai mult) | ✅ Full voice spectrum |
| Latență | ~5-10ms | Doar ADC/DAC |
| Claritate | ★★★★★ | Cristalină |
| Naturalețe | ★★★★★ | Voce naturală |

---

## Chain-ul Complet de Procesare

### RX Path (stație locală → reflector)
```
1. Stație locală transmite FM
   Signal: RF analog, 12.5 kHz deviation

2. GM340 RX demodulează
   Output: Audio analog (discriminator/line)
   Bandwidth: 300-3000 Hz (FM receiver)
   Level: 0.5-1.0V RMS

3. MMDVM ADC
   Input: Analog audio
   Process: 8 kHz sampling, 16-bit quantization
   Output: PCM digital
   SNR: ~85 dB (16-bit)

4. MMDVMHost (FM mode)
   Input: PCM 8 kHz
   Process: Pass-through (no processing)
   Output: PCM 8 kHz
   Latency: ~2ms

5. Analog_Bridge
   Input: PCM 8 kHz
   Process: Encapsulate în USRP protocol
   Output: UDP frames (160 samples/20ms)
   Latency: ~2ms

6. SVXLink UsrpLogic
   Input: USRP frames 8 kHz
   Process:
     - AudioDecoder (S16) - extrage PCM
     - AudioInterpolator (8 kHz → 16 kHz) - FIR filter
     - AudioFilter (BpBu1/300-3400) - cleanup
     - AudioCompressor (-3.0 dBFS) - gentle limiting
   Output: PCM 16 kHz
   Latency: ~5ms
   Quality: ★★★★★ (transparent)

7. SVXLink Logic → Reflector
   Codec: Opus 32 kbps (sau Speex/GSM)
   Bandwidth: 50-3400 Hz preserved
   Latency: ~10-20ms (codec)
   Quality: ★★★★☆ (foarte bună)

TOTAL RX LATENCY: ~29-39ms (local)
                  +50-100ms (internet la reflector)
                  = 79-139ms (acceptabil)
```

### TX Path (reflector → stație locală)
```
1. Reflector → SVXLink
   Codec: Opus/Speex decode
   Output: PCM 16 kHz
   Latency: ~10-20ms

2. SVXLink UsrpLogic
   Input: PCM 16 kHz
   Process:
     - AudioFilter (BpBu1/300-3400) - cleanup
     - AudioDecimator (16 kHz → 8 kHz) - FIR filter
     - AudioCompressor (-3.0 dBFS) - gentle limiting
     - AudioEncoder (S16) - raw PCM
   Output: USRP frames 8 kHz
   Latency: ~5ms

3. Analog_Bridge
   Input: USRP frames
   Process: Extract PCM
   Output: PCM 8 kHz
   Latency: ~2ms

4. MMDVMHost (FM mode)
   Input: PCM 8 kHz
   Process: PTT control + pass-through
   Output: PCM 8 kHz + PTT signal
   Latency: ~2ms

5. MMDVM DAC
   Input: PCM 8 kHz
   Process: Digital → analog conversion
   Output: Analog audio
   Level: 0.5-1.0V RMS
   SNR: ~85 dB

6. GM340 TX modulează
   Input: Analog audio
   Output: RF FM modulated
   Deviation: 12.5 kHz max
   Latency: ~5ms

TOTAL TX LATENCY: ~34-44ms (local)
                  +50-100ms (internet de la reflector)
                  = 84-144ms (acceptabil)

ROUND-TRIP: ~163-283ms (bun pentru conversație)
```

---

## De ce sună mult mai bine decât DMR→Analog

### 1. **Fără Codec AMBE**
```
DMR path:
  Audio → AMBE encoder (pierdere) → AMBE decoder (zgomot) → Audio degradat

Analog path:
  Audio → PCM (perfect) → PCM (perfect) → Audio original
```

### 2. **Fără Band-Limiting Agresiv**
```
DMR: 300-3400 Hz (standard telefonie, restrictiv)
Analog: 50-3400 Hz (sau mai mult, depinde de filtrul GM340)

Rezultat: bași mai plini, claritate crescută în înalte
```

### 3. **Fără AGC Agresiv**
```
DMR: AGC foarte agresiv pentru a compensa variații în RF
Analog: Dinamică naturală (doar gentle limiting la -3dB)

Rezultat: voce mai naturală, fără "pumping" effect
```

### 4. **Fără Artifacts de Compresie**
```
DMR: Glitch-uri audibile la sibilante (s, f, sh)
Analog: Zero artifacts (PCM = reprezentare perfectă)

Rezultat: consoane clare, voce cristalină
```

---

## Ajustări Fine pentru Calitate Maximă

### 1. Optimizează Nivelurile Audio

```bash
# Test audio RX (de la MMDVM)
# Transmite cu o stație pe frecvența RX
# Monitorizează nivelul în SVXLink:

tail -f /var/log/svxlink.log | grep -i "level"

# Dacă vezi:
# - "Audio too hot" sau clipping → reduce RXLevel în MMDVM.ini
# - "Audio too low" → crește RXLevel în MMDVM.ini

# Valori optime: RXLevel=40-60 (în MMDVM.ini)
```

```bash
# Test audio TX (către MMDVM)
# Vorbește în reflector, monitorizează pe receptor local

# Dacă auzi:
# - Distorsiune → reduce TXLevel în MMDVM.ini
# - Audio prea slab → crește TXLevel în MMDVM.ini

# Valori optime: TXLevel=40-60 (în MMDVM.ini)
```

### 2. Fine-Tune Filters

```ini
# În svxlink.conf

# Pentru voce masculină (bași mai plini):
FILTER_TO_USRP=BpBu1/200-3400
FILTER_FROM_USRP=BpBu1/200-3400

# Pentru voce feminină (claritate crescută):
FILTER_TO_USRP=BpBu1/300-3800
FILTER_FROM_USRP=BpBu1/300-3800

# Pentru maxim bandwidth (calitate supremă):
FILTER_TO_USRP=BpBu1/100-3800
FILTER_FROM_USRP=BpBu1/100-3800
# ⚠️ Necesită bandwidth bun la GM340 (>6 kHz)
```

### 3. Elimină Compresie Completă (experimental)

```ini
# În svxlink.conf
# Pentru ZERO procesare (transparență absolută)

# PREAMP=0
# FILTER_TO_USRP=           # Comentat = fără filtrare
# LOCAL_LIMITER_THRESH=     # Comentat = fără limiting
#
# NET_PREAMP=0
# FILTER_FROM_USRP=         # Comentat = fără filtrare
# NET_LIMITER_THRESH=       # Comentat = fără limiting

# ⚠️ RISC: Clipping posibil dacă nivelele nu sunt perfect ajustate
# Folosește doar dacă ai experiență și poți monitoriza distorsiunile
```

---

## Verificare Calitate Audio

### Test Subjectiv (recomandat)

```
1. Recepție voce naturală:
   ✅ Consoane clare (s, f, t, k)
   ✅ Bași plini (voce masculină)
   ✅ Înalte cristaline (voce feminină)
   ✅ ZERO "robotică" sau artifacts
   ✅ Dinamică naturală (fără pumping)

2. Transmisie voce naturală:
   ✅ Feedback pozitiv de la receptori ("sună foarte bine")
   ✅ Claritate echivalentă cu FM direct (fără degradare)
```

### Test Obiectiv (opțional)

```bash
# Înregistrează audio și analizează:

# 1. Înregistrare RX audio (de la reflector)
arecord -D hw:0,0 -f S16_LE -r 16000 -c 1 test_rx.wav -d 10

# 2. Analizează spectru
sox test_rx.wav -n spectrogram -o test_rx_spectrum.png

# 3. Verifică:
#    - Bandwidth: ar trebui să vezi energie de la 300-3400 Hz
#    - SNR: ar trebui >60 dB (fără zgomot excesiv)
#    - THD: ar trebui <1% (fără distorsiune)
```

---

## Concluzie: Avantaje Setup Analog Curat

### vs DMR→Analog
```
                    DMR→Analog    Analog Direct PCM
Claritate voce      ★★☆☆☆        ★★★★★
Naturalețe          ★☆☆☆☆        ★★★★★
Bandwidth           300-3400 Hz   50-3400+ Hz
Latență             ~40-60ms      ~5-10ms
Complexitate        MARE          SIMPLĂ
Costuri             DV3000 $150+  $0 (fără codec)
Artifacts           DA (AMBE)     NU
```

### Setup-ul tău este PERFECT pentru:
✅ Calitate audio maximă
✅ Latență minimă
✅ Complexitate redusă (fără transcoding)
✅ Costuri reduse (fără DV3000)
✅ Voce naturală (fără robotică DMR)

### NU ai nevoie de:
❌ AMBE codec (DV3000, md380-emu)
❌ Digital voice transcoding
❌ DMR metadata (TG, CC, TS)
❌ Procesare digitală complexă

**Pur și simplu PCM analog de calitate! 🎵**
