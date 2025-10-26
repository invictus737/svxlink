# VOICE ACTIVITY DETECTION & ANTI-KERCHUNKING ÎN SVXLINK

## Introducere

SVXLink include un sistem sofisticat de **Voice Activity Detection (VAD)** și **anti-kerchunking** bazat pe mai multe straturi de detectare. Acest document explică cum să configurezi sistemul pentru a transmite către reflector **DOAR** transmisiile care conțin voce efectivă, blocând:
- **Kerchunking** (deschidere scurtă repetor, fără modulație)
- **Testare RF** (portabil opening squelch, dar fără vorbire)
- **Zgomot sau interferențe** (fără voce reală)

**Acuratețe țintă:** 90%+ detectare voce reală vs non-voce

---

## TABLE OF CONTENTS

1. [Arhitectura Sistemului de Detectare](#1-arhitectura-sistemului-de-detectare)
2. [Componente Cheie](#2-componente-cheie)
3. [Configurare Anti-Kerchunk Profesională](#3-configurare-anti-kerchunk-profesională)
4. [Implementare Voice Activity Detection](#4-implementare-voice-activity-detection)
5. [Strategie Multi-Layer pentru 90%+ Acuratețe](#5-strategie-multi-layer-pentru-90-acuratețe)
6. [Configurare Completă Repetor cu VAD](#6-configurare-completă-repetor-cu-vad)
7. [Monitorizare și Fine-Tuning](#7-monitorizare-și-fine-tuning)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. ARHITECTURA SISTEMULUI DE DETECTARE

### 1.1 Straturi de Protecție

SVXLink folosește o arhitectură **multi-layer** pentru detectarea vocii:

```
┌────────────────────────────────────────────────────────┐
│ Layer 1: Squelch (Hardware/Software)                  │
│  - Detectare prezență semnal RF                       │
│  - CTCSS/SIGLEV/VOX/NOISE                             │
└────────────────┬───────────────────────────────────────┘
                 │ Signal Present?
                 ▼
┌────────────────────────────────────────────────────────┐
│ Layer 2: SQL_START_DELAY                              │
│  - Blocare după TX OFF (50-150ms)                     │
│  - Previne false triggers de la transiente            │
└────────────────┬───────────────────────────────────────┘
                 │ Delay Expired?
                 ▼
┌────────────────────────────────────────────────────────┐
│ Layer 3: SQL_DELAY                                    │
│  - Settling time pentru detectori (20-100ms)          │
│  - Crucial pentru sisteme voter                       │
└────────────────┬───────────────────────────────────────┘
                 │ Signal Stable?
                 ▼
┌────────────────────────────────────────────────────────┐
│ Layer 4: SQL_HANGTIME ⭐ PRIMARY ANTI-KERCHUNK        │
│  - Menține squelch deschis (100-2000ms)               │
│  - Previne închidere la dropouts scurte               │
│  - Extended hangtime la semnal slab                   │
└────────────────┬───────────────────────────────────────┘
                 │ Hangtime Active?
                 ▼
┌────────────────────────────────────────────────────────┐
│ Layer 5: SQL_TIMEOUT                                  │
│  - Hard timeout (180-600 sec)                         │
│  - Previne blocarea repetor                           │
│  - Warning tone la expirare                           │
└────────────────┬───────────────────────────────────────┘
                 │ Valid Transmission?
                 ▼
          ┌──────────────┐
          │ Squelch OPEN │
          └──────────────┘
```

### 1.2 Timp de Procesare

```
Event: Stație locală transmite
  ↓
t=0ms:    GM340 RX primește semnal RF
t=5ms:    MMDVM ADC convertește analog → digital
t=10ms:   Squelch detectează semnal (CTCSS/SIGLEV/VOX)
t=60ms:   SQL_START_DELAY expiră (50ms) ⭐
t=110ms:  SQL_DELAY expiră (50ms) ⭐
t=110ms:  Squelch OPEN → Audio flow începe
          ↓
          Audio transmis către SVXLink
          ↓
Event: Stație locală oprește transmisia
  ↓
t=0ms:    Semnal RF dispare
t=0ms:    Squelch detector → signal lost
t=0ms:    SQL_HANGTIME activat (200-500ms) ⭐ ANTI-KERCHUNK
t=200ms:  SQL_HANGTIME expiră (fără re-trigger)
t=200ms:  Squelch CLOSE → Audio flow se oprește

TOTAL DELAY OPEN: ~110ms (START_DELAY + DELAY)
TOTAL HANGTIME: ~200ms (minimum pentru anti-kerchunk)
```

---

## 2. COMPONENTE CHEIE

### 2.1 Squelch (Clasa de Bază)

**Fișier:** `src/svxlink/trx/Squelch.h` (438 linii), `Squelch.cpp` (392 linii)

**State Machine:**
```cpp
// Squelch.cpp:200-274
int Squelch::writeSamples(const float *samples, int count) {
  // Layer 5: Timeout check
  if (m_timeout_left == 0) {
    // Hard closure - timeout exceeded
    setOpen(false);
    return count;
  }

  // Layer 2: Start delay check (deaf after TX)
  if (m_start_delay_left > 0) {
    // Still in start delay - ignore signal
    m_start_delay_left = max(0, m_start_delay_left - count);
    return count;
  }

  // Layer 1: Process samples through detector
  int ret = processSamples(samples, count);

  // Layer 3: Delay handling (delayed open)
  if (m_signal_detected && !m_open) {
    if (m_delay > 0) {
      if (m_delay_left == 0) {
        m_delay_left = m_delay;
      }
      m_delay_left = max(0, m_delay_left - ret);
      if (m_delay_left == 0) {
        // Delay expired - open squelch
        setOpen(true);
      }
    } else {
      setOpen(true);
    }
  }

  // Layer 4: Hangtime handling (delayed close)
  if (!m_signal_detected && m_open) {
    if (m_current_hangtime > 0) {
      if (m_hangtime_left == 0) {
        m_hangtime_left = m_current_hangtime;
      }
      m_hangtime_left = max(0, m_hangtime_left - ret);
      if (m_hangtime_left == 0) {
        // Hangtime expired - close squelch
        setOpen(false);
      }
    } else {
      setOpen(false);
    }
  }

  return ret;
}
```

**Parametri de Configurare:**

| Parametru | Valori Tipice | Unitate | Scop |
|-----------|---------------|---------|------|
| **SQL_START_DELAY** | 50-150 | ms | Blocare după TX OFF (previne transiente) |
| **SQL_DELAY** | 20-100 | ms | Settling time pentru detector |
| **SQL_HANGTIME** | 100-2000 | ms | ⭐ **PRIMARY ANTI-KERCHUNK** |
| **SQL_EXTENDED_HANGTIME** | 1000-3000 | ms | Hangtime crescut la semnal slab |
| **SQL_EXTENDED_HANGTIME_THRESH** | 5-20 | siglev | Prag activare extended hangtime |
| **SQL_TIMEOUT** | 180-600 | sec | Hard timeout (forțează close) |

### 2.2 SquelchVox (Voice-Operated Switch)

**Fișier:** `src/svxlink/trx/SquelchVox.h` (172 linii), `SquelchVox.cpp` (249 linii)

**Algoritm:**
```cpp
// SquelchVox.cpp:processSamples()
int SquelchVox::processSamples(const float *samples, int count) {
  for (int i = 0; i < count; i++) {
    // Circular buffer - rolling window RMS
    float old_sample = buf[head];
    float new_sample = samples[i];
    buf[head] = new_sample;
    head = (head + 1) % buf_size;

    // Update sum of squares
    sum -= old_sample * old_sample;
    sum += new_sample * new_sample;

    // Calculate RMS (Root Mean Square)
    double rms = sqrt(sum / buf_size);

    // Hysteresis - separate thresholds up/down
    if (!signalDetected() && (rms >= up_thresh)) {
      // Signal detected - squelch open
      setSignalDetected(true);
    } else if (signalDetected() && (rms < down_thresh)) {
      // Signal lost - squelch close (with hangtime)
      setSignalDetected(false);
    }
  }
  return count;
}
```

**Parametri de Configurare:**

| Parametru | Valori Tipice | Scop |
|-----------|---------------|------|
| **VOX_FILTER_DEPTH** | 100-500 | ms - rolling window size |
| **VOX_THRESH** | 2000-5000 | Threshold pentru detecție voce |
| **VOX_OPEN_THRESH** | 4000 | Prag deschidere (voce detectată) |
| **VOX_CLOSE_THRESH** | 2000 | Prag închidere (hysteresis) |

**De ce funcționează:**
- **RMS energy** detectează voce (variații mari energie)
- **Hysteresis** (up_thresh > down_thresh) previne chatter
- **Rolling window** (100-500ms) filtrează zgomot impulsiv

### 2.3 SigLevDetNoise (Detectare Nivel Semnal)

**Fișier:** `src/svxlink/trx/SigLevDetNoise.h` (248 linii)

**Algoritm:**
```
1. Filtrează audio prin bandpass (300-3000 Hz)
2. Calculează energie instantanee
3. Construiește set sortat energie (integration time)
4. Calculează median/percentile energie
5. Mapează la siglev (0-100)
6. Detectează bogus threshold (audio squelched)
```

**Parametri de Configurare:**

| Parametru | Valori Tipice | Scop |
|-----------|---------------|------|
| **SIGLEV_DET_INTEGRATION_TIME** | 200-500 | ms - averaging window |
| **SIGLEV_DET_BOGUS_THRESH** | 100-150 | Threshold pentru audio squelched |
| **SIGLEV_SLOPE** | 1.0 | Slope calibrare siglev |
| **SIGLEV_OFFSET** | 0.0 | Offset calibrare siglev |

**Bogus Threshold:**
```
Problema: Receptor cu audio squelched (silence când nu e semnal)
         → Detector interpretează silence = signal foarte puternic

Soluție: Bogus threshold (e.g., 120)
         → Dacă siglev > 120, returnează 0 (squelch închis)

Recomandare: Folosește discriminator output (unsquelched audio)
```

### 2.4 AudioStreamStateDetector

**Fișier:** `src/async/audio/AsyncAudioStreamStateDetector.h` (291 linii)

**State Machine:**
```
IDLE (is_active=false, is_idle=true)
  ↓ writeSamples() called
ACTIVE (is_active=true, is_idle=false)
  ↓ flushSamples() called
FLUSHING (is_active=false, is_idle=false)
  ↓ allSamplesFlushed() called
IDLE
```

**Semnale:**
```cpp
sigStreamStateChanged(bool is_active, bool is_idle);
sigStreamIsActive(bool is_active);
sigStreamIsIdle(bool is_idle);
```

**Utilizare pentru VAD:**
```cpp
// În UsrpLogic sau Logic
m_logic_con_in->sigStreamStateChanged.connect(
  sigc::mem_fun(*this, &Logic::onStreamStateChanged)
);

void Logic::onStreamStateChanged(bool is_active, bool is_idle) {
  if (is_idle) {
    // Transmisia s-a terminat
    // AICI poți implementa minimum duration check
    if (transmission_duration < MIN_DURATION) {
      // Kerchunk detectat - NU transmite la reflector
      log("Kerchunk detected - blocked");
      return;
    }
    // Transmisie validă - trimite la reflector
  }
}
```

---

## 3. CONFIGURARE ANTI-KERCHUNK PROFESIONALĂ

### 3.1 Parametri Critici

**SQL_HANGTIME = 200-500ms** ⭐ CEA MAI IMPORTANTĂ SETARE

```ini
[Rx1]
# ⭐ PRIMARY ANTI-KERCHUNK
SQL_HANGTIME=300              # 300ms hangtime (recommended)

# Explicație:
# - Kerchunking tipic: 50-200ms (prea scurt pentru voce)
# - Voce reală: >500ms (multiple silabe)
# - Hangtime 300ms:
#   - Permite transmisii scurte (1-2 cuvinte)
#   - Blochează kerchunk pur (quick key-up)
#   - Reduce re-deschideri multiple (audio choppy)
```

**SQL_EXTENDED_HANGTIME** pentru semnal slab:

```ini
[Rx1]
SQL_HANGTIME=300
SQL_EXTENDED_HANGTIME=1000    # 1 second pentru semnal slab
SQL_EXTENDED_HANGTIME_THRESH=15  # Sub siglev 15

# Explicație:
# - Semnal slab → dropouts frecvente
# - Extended hangtime menține squelch deschis
# - Previne "pickling" (deschide-închide rapid)
```

**SQL_START_DELAY** pentru TX OFF transients:

```ini
[Rx1]
SQL_START_DELAY=100           # 100ms după TX OFF

# Explicație:
# - Repetor duplex: TX OFF → RX ON
# - Transiente de la commutare pot deschide squelch
# - Start delay = deaf period după TX
```

**SQL_DELAY** pentru voter sau multiple receivers:

```ini
[Rx1]
SQL_DELAY=50                  # 50ms settling time

# Explicație:
# - Voter: multiple receivers, trebuie să compare siglev
# - Delay permite stabilizare măsurători
# - Previne switch rapid între receivers
```

**SQL_TIMEOUT** protection:

```ini
[Rx1]
SQL_TIMEOUT=180               # 3 minute hard timeout

# Explicație:
# - Previne transmisii infinite (stuck PTT)
# - Warning tone la 170 sec (squelch_timeout.tcl)
# - Force close la 180 sec
```

### 3.2 Configurare Completă Anti-Kerchunk

```ini
[Rx1]
TYPE=Local                    # Local receiver (GM340 RX)
AUDIO_DEV=alsa:plughw:1       # MMDVM audio device
AUDIO_CHANNEL=0               # Mono
AUDIO_GAIN=0                  # Unity gain (adjust MMDVM RXLevel)

# ⭐ SQUELCH TYPE
SQL_DET=NOISE                 # Signal level detector (NOISE/SIGLEV)
SQUELCH=VOX                   # Voice-operated squelch

# ⭐ VOX CONFIGURATION (Voice Activity Detection)
VOX_FILTER_DEPTH=300          # 300ms rolling window
VOX_THRESH=3000               # Threshold pentru voce (tune!)

# ⭐ SIGNAL LEVEL DETECTOR
SIGLEV_DET_INTEGRATION_TIME=300   # 300ms integration
SIGLEV_DET_BOGUS_THRESH=120       # Bogus threshold (squelched audio)

# ⭐ ANTI-KERCHUNK TIMING
SQL_START_DELAY=100           # 100ms deaf după TX OFF
SQL_DELAY=50                  # 50ms settling time
SQL_HANGTIME=300              # ⭐ 300ms PRIMARY ANTI-KERCHUNK
SQL_EXTENDED_HANGTIME=1000    # 1 sec pentru semnal slab
SQL_EXTENDED_HANGTIME_THRESH=15   # Threshold siglev pentru extended
SQL_TIMEOUT=180               # 3 minute hard timeout

# ⭐ SIGLEV THRESHOLDS (dacă folosești SIGLEV squelch)
SQL_SIGLEV_OPEN_THRESH=20     # Deschide la siglev >= 20
SQL_SIGLEV_CLOSE_THRESH=10    # Închide la siglev < 10 (hysteresis)
```

---

## 4. IMPLEMENTARE VOICE ACTIVITY DETECTION

### 4.1 Strategie: VOX + Hangtime

**Configurare Recommended:**

```ini
[Rx1]
# STEP 1: VOX pentru detectare voce
SQUELCH=VOX
VOX_FILTER_DEPTH=300          # 300ms window (tune pentru voce rapidă/lentă)
VOX_THRESH=3000               # Start aici, tune în funcție de nivel audio

# STEP 2: Hangtime pentru anti-kerchunk
SQL_HANGTIME=300              # 300ms = minimum voce reală
SQL_EXTENDED_HANGTIME=1000    # 1 sec pentru semnal slab/mobile

# STEP 3: Protection
SQL_START_DELAY=100           # Previne TX transients
SQL_TIMEOUT=180               # Hard timeout 3 min
```

**De ce funcționează:**
1. **VOX detectează voce** (RMS energy > threshold)
2. **Hangtime elimină kerchunk** (transmisii < 300ms blocate)
3. **Extended hangtime pentru mobile** (previne dropouts la semnal slab)

### 4.2 Tuning VOX_THRESH

**Procedură:**

```bash
# 1. Pornește SVXLink cu debug
sudo svxlink --logfile=- --config=/etc/svxlink/svxlink.conf

# 2. Monitorizează nivelul audio
# Transmite voce normală, observă:
# - RMS value când vorbești: ~3000-8000 (depinde de mic gain)
# - RMS value la zgomot: ~500-1500

# 3. Setează VOX_THRESH
# Regulă: VOX_THRESH = (zgomot_max * 1.5) la (voce_min * 0.7)
# Exemplu:
#   Zgomot: 1200 RMS
#   Voce: 4000 RMS
#   VOX_THRESH = 1200 * 1.5 = 1800 (prea slab, false triggers)
#   VOX_THRESH = 4000 * 0.7 = 2800 (bun, detectează voce)
#
# Recommended: VOX_THRESH = 3000 (start point)

# 4. Test kerchunk
# a) Quick key-up (50-100ms, fără modulație)
#    → Squelch ar trebui să NU se deschidă (sub VOX_THRESH)
#
# b) Quick key-up cu modulație (200ms, fără voce)
#    → Squelch se deschide, dar SQL_HANGTIME < 300ms
#    → NU trimite la reflector (prea scurt)
#
# c) Voce reală (>500ms)
#    → Squelch se deschide, SQL_HANGTIME menține deschis
#    → Transmite la reflector

# 5. Ajustare fină
# - Dacă false negatives (voce slabă NU detectată):
#   VOX_THRESH -= 500
#
# - Dacă false positives (zgomot detectat ca voce):
#   VOX_THRESH += 500
```

### 4.3 Detectare Minimum Duration în Logic

**Implementare Custom în UsrpLogic:**

```cpp
// În UsrpLogic.h
class UsrpLogic : public LogicBase {
private:
  std::chrono::steady_clock::time_point m_transmission_start;
  std::chrono::milliseconds MIN_TRANSMISSION_DURATION{500}; // 500ms
  bool m_transmission_active = false;
};

// În UsrpLogic.cpp
void UsrpLogic::onLogicConInStreamStateChanged(bool is_active, bool is_idle) {
  if (is_active && !m_transmission_active) {
    // Transmisia a început
    m_transmission_start = std::chrono::steady_clock::now();
    m_transmission_active = true;
    log(LOGINFO, "Transmission started");
  }

  if (is_idle && m_transmission_active) {
    // Transmisia s-a terminat
    auto now = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
      now - m_transmission_start
    );

    log(LOGINFO, "Transmission ended, duration: " +
        std::to_string(duration.count()) + "ms");

    // ⭐ CHECK MINIMUM DURATION
    if (duration < MIN_TRANSMISSION_DURATION) {
      log(LOGWARN, "Kerchunk detected (" +
          std::to_string(duration.count()) + "ms < " +
          std::to_string(MIN_TRANSMISSION_DURATION.count()) + "ms) - BLOCKED");

      // NU trimite sendStopMsg() sau alte acțiuni
      // Doar logheaza și ignoră transmisia
      m_transmission_active = false;
      return;
    }

    // Transmisie validă - continuă normal
    log(LOGINFO, "Valid transmission (" +
        std::to_string(duration.count()) + "ms) - forwarding to reflector");

    sendStopMsg();
    m_transmission_active = false;
  }

  checkIdle();
}
```

**Configurare MIN_DURATION:**

```ini
[UsrpLogic]
# Adaugă parametru custom
MIN_TRANSMISSION_DURATION=500  # milliseconds

# În UsrpLogic::initialize()
int min_dur = 500;
cfg.getValue(name(), "MIN_TRANSMISSION_DURATION", min_dur);
MIN_TRANSMISSION_DURATION = std::chrono::milliseconds(min_dur);
```

---

## 5. STRATEGIE MULTI-LAYER PENTRU 90%+ ACURATEȚE

### 5.1 Combinare Detectorilor

**Configurare Dual Squelch:**

```ini
[Rx1]
# LAYER 1: VOX pentru voce
SQUELCH=COMBINE
SQL_COMBINE=VOX AND SIGLEV    # VOX detectează voce + SIGLEV confirmă RF

# VOX Configuration
VOX_FILTER_DEPTH=300
VOX_THRESH=3000

# SIGLEV Configuration
SQL_DET=NOISE
SQL_SIGLEV_OPEN_THRESH=15     # Minimum siglev pentru valid signal
SQL_SIGLEV_CLOSE_THRESH=10

# LAYER 2: Timing Anti-Kerchunk
SQL_START_DELAY=100
SQL_DELAY=50
SQL_HANGTIME=400              # Crescut pentru dual squelch
SQL_EXTENDED_HANGTIME=1200
SQL_TIMEOUT=180

# LAYER 3: Integration time (noise detector)
SIGLEV_DET_INTEGRATION_TIME=400   # Longer integration = mai stable
```

**Logica:**
```
Squelch opens DOAR dacă:
  1. VOX detectează voce (RMS > threshold)
     AND
  2. SIGLEV confirmă RF present (siglev > 15)

Rezultat:
  - Zgomot local (fără RF): VOX = YES, SIGLEV = NO → BLOCKED
  - Kerchunk (RF fără voce): VOX = NO, SIGLEV = YES → BLOCKED
  - Voce reală (RF + voce): VOX = YES, SIGLEV = YES → ALLOWED
```

### 5.2 Filtrare TCL Events

**În events.tcl:**

```tcl
# Interceptare squelch open
proc squelch_open {rx_name} {
  # Obține siglev curent
  set siglev [rx_siglev $rx_name]

  # Obține squelch activity info
  set info [rx_activity_info $rx_name]

  # LOG
  puts "Squelch opened on $rx_name: siglev=$siglev, info=$info"

  # ⭐ FILTER: Minimum siglev
  if {$siglev < 20} {
    puts "WARNING: Low siglev ($siglev) - possible noise"
    # Poți adăuga logică custom aici
  }
}

# Interceptare squelch close
proc squelch_close {rx_name} {
  # Obține durata squelch open
  set duration [rx_squelch_duration $rx_name]

  puts "Squelch closed on $rx_name: duration=${duration}ms"

  # ⭐ FILTER: Minimum duration
  if {$duration < 500} {
    puts "WARNING: Short transmission (${duration}ms) - possible kerchunk"
    playMsg "Core" "kerchunk_detected"
    # NU continua cu transmisie la reflector
    return
  }

  # Transmisie validă
  puts "Valid transmission: ${duration}ms"
}
```

### 5.3 Statistici în Timp Real

**Adaugă logging pentru tuning:**

```tcl
# În events.tcl
set ::kerchunk_count 0
set ::valid_transmission_count 0

proc squelch_close {rx_name} {
  global kerchunk_count valid_transmission_count

  set duration [rx_squelch_duration $rx_name]
  set siglev [rx_siglev $rx_name]

  if {$duration < 500} {
    incr kerchunk_count
    set ratio [expr {double($valid_transmission_count) /
                     ($kerchunk_count + $valid_transmission_count) * 100}]
    puts "KERCHUNK #$kerchunk_count detected (${duration}ms, siglev=$siglev)"
    puts "STATS: Valid=${valid_transmission_count}, Kerchunk=${kerchunk_count}, Valid%=${ratio}%"
  } else {
    incr valid_transmission_count
    puts "VALID transmission #$valid_transmission_count (${duration}ms, siglev=$siglev)"
  }
}
```

---

## 6. CONFIGURARE COMPLETĂ REPETOR CU VAD

### 6.1 svxlink.conf (Anti-Kerchunk Optimal)

```ini
[GLOBAL]
MODULE_PATH=/usr/lib/svxlink
LOGICS=UsrpLogic
CFG_DIR=/etc/svxlink/svxlink.d
TIMESTAMP_FORMAT="%c"
CARD_SAMPLE_RATE=16000
CARD_CHANNELS=1

# ════════════════════════════════════════════════════════
# RX1: GM340 RX → MMDVM (cu VAD anti-kerchunk)
# ════════════════════════════════════════════════════════
[Rx1]
TYPE=Local
AUDIO_DEV=alsa:plughw:1
AUDIO_CHANNEL=0

# ⭐ VOICE ACTIVITY DETECTION
SQUELCH=COMBINE
SQL_COMBINE=VOX AND SIGLEV    # Dual-layer: voce + RF

# VOX Configuration (detectare voce)
VOX_FILTER_DEPTH=300          # 300ms rolling window
VOX_THRESH=3000               # Threshold (tune!)

# SIGLEV Configuration (detectare RF)
SQL_DET=NOISE
SIGLEV_DET_INTEGRATION_TIME=400
SIGLEV_DET_BOGUS_THRESH=120
SQL_SIGLEV_OPEN_THRESH=18     # Minimum RF pentru valid signal
SQL_SIGLEV_CLOSE_THRESH=12    # Hysteresis

# ⭐ ANTI-KERCHUNK TIMING
SQL_START_DELAY=100           # 100ms deaf după TX OFF
SQL_DELAY=50                  # 50ms settling time
SQL_HANGTIME=400              # ⭐ 400ms primary anti-kerchunk
SQL_EXTENDED_HANGTIME=1200    # 1.2 sec pentru semnal slab
SQL_EXTENDED_HANGTIME_THRESH=15
SQL_TIMEOUT=180               # 3 minute hard timeout

# Audio levels
AUDIO_GAIN=0                  # Ajustează în MMDVM.ini (RXLevel)

# PTT (NU folosim - repetor receive-only pe Rx1)
# PTT_TYPE=NONE

# ════════════════════════════════════════════════════════
# UsrpLogic: Bridge către reflector
# ════════════════════════════════════════════════════════
[UsrpLogic]
TYPE=Usrp
CALLSIGN=YourCall

# Network (Analog_Bridge)
USRP_HOST=127.0.0.1
USRP_TX_PORT=41234
USRP_RX_PORT=41233

# ⭐ MINIMUM TRANSMISSION DURATION (custom parameter)
MIN_TRANSMISSION_DURATION=500 # 500ms minimum pentru voce reală

# Audio Processing
PREAMP=0
NET_PREAMP=0
FILTER_TO_USRP=BpBu1/300-3400
FILTER_FROM_USRP=BpBu1/300-3400
LOCAL_LIMITER_THRESH=-3.0
NET_LIMITER_THRESH=-3.0

# Event handler
EVENT_HANDLER=/usr/share/svxlink/events.tcl

# Debug
DEBUG=2                       # INFO level pentru monitoring

# Parametri DMR (nu folosiți în mod analog)
DMRID=0
RPTID=0
DEFAULT_TG=0
DEFAULT_CC=0
DEFAULT_TS=0
```

### 6.2 MMDVM.ini (FM Mode Optimized)

```ini
[General]
Callsign=YourCall
Timeout=180
Duplex=1
ModeHang=5

# DOAR FM activat
[FM Network]
Enable=1
LocalAddress=127.0.0.1
LocalPort=32768
GatewayAddress=127.0.0.1
GatewayPort=31000

# ⭐ Audio Quality
RFAudioBoost=1.0              # Natural (fără boost artificial)
MaxDevLevel=90                # 90% max deviation

# Squelch (handled by SVXLink, dar configurăm backup)
NoiseSquelch=10               # Low threshold (SVXLink controlează)
SquelchHighThreshold=30
SquelchLowThreshold=20

# Timing
ModeHang=5                    # Reduced pentru latență
Timeout=180                   # Match cu SVXLink SQL_TIMEOUT

# Callsign announce
CallsignAtStart=0             # Dezactivat (SVXLink gestionează)
CallsignAtEnd=0
RFAck=K
NetAck=N

[Modem]
Port=/dev/ttyACM0
Protocol=uart
TXInvert=0
RXInvert=0
PTTInvert=0
TXDelay=50
RXLevel=50                    # ⭐ Ajustează pentru nivel audio optim
TXLevel=50                    # ⭐ Ajustează pentru TX audio
RXOffset=0
TXOffset=0
RXDCOffset=0
TXDCOffset=0

# Dezactivează modurile digitale
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
```

### 6.3 Analog_Bridge.ini (Transparent Audio)

```ini
[GENERAL]
decoderFallBack = false       # Nu folosim decoder AMBE
useEmulator = false
useExternalDV3000 = false
useExternalMD380 = false
logLevel = 2

[USRP]
address = 127.0.0.1
txPort = 41234
rxPort = 41233
usrpAudioPort = 32768

[MMDVM]
address = 127.0.0.1
rxPort = 32768
txPort = 31000

# ⭐ Audio Processing (transparent, NU AGC)
[AUDIO]
to_usrp_gain = 1.0
to_usrp_shape = AUDIO_USE_GAIN  # Transparent (NU AGC!)

to_mmdvm_gain = 1.0
to_mmdvm_shape = AUDIO_USE_GAIN # Transparent (NU AGC!)

[INFORMATION]
mode = FM
subscriber = YourCall
latitude = 0.0
longitude = 0.0
description = Analog FM Repeater with VAD
```

---

## 7. MONITORIZARE ȘI FINE-TUNING

### 7.1 Monitoring în Timp Real

```bash
# Terminal 1: SVXLink log (live)
tail -f /var/log/svxlink.log | grep -E "Squelch|siglev|duration"

# Terminal 2: MMDVM log
tail -f /var/log/mmdvm.log | grep -E "FM|audio"

# Terminal 3: Analog_Bridge log
tail -f /var/log/analog_bridge.log | grep -E "USRP|MMDVM"

# Terminal 4: System stats
watch -n 1 '
echo "=== SVXLink Status ==="
systemctl status svxlink | grep Active
echo ""
echo "=== UDP Traffic ==="
netstat -s | grep "packets received"
echo ""
echo "=== Audio Levels ==="
# Verifică nivelele audio (dacă ai tool)
'
```

### 7.2 Test Suite

**Test 1: Kerchunk Detection**

```bash
# Obiectiv: Kerchunk (quick key-up) NU ar trebui să deschidă squelch

# Procedură:
# 1. Quick key-up pe frecvența RX (50-100ms, fără modulație)
# 2. Observă log SVXLink:

# Expected (SUCCES):
# - NU vezi "Squelch opened"
# - VOX threshold nu e atins (zgomot prea slab)

# Dacă vezi "Squelch opened" (FAIL):
# - VOX_THRESH prea slab → crește cu 500
# - SAU SQL_START_DELAY prea scurt → crește la 150ms
```

**Test 2: Quick Modulation Detection**

```bash
# Obiectiv: Quick modulation (200ms, cu carrier dar fără voce)
#           ar trebui blocat de SQL_HANGTIME

# Procedură:
# 1. Transmite carrier cu modulație (200ms, fără vorbire)
# 2. Observă log SVXLink:

# Expected (SUCCES):
# - Vezi "Squelch opened" (OK, modulație detectată)
# - Vezi "Squelch closed" după ~200ms
# - Vezi "Short transmission (200ms) - possible kerchunk" (BLOCAT)

# Dacă transmisia ajunge la reflector (FAIL):
# - SQL_HANGTIME prea scurt → crește la 400-500ms
# - SAU MIN_TRANSMISSION_DURATION prea mic → crește la 600ms
```

**Test 3: Valid Voice Detection**

```bash
# Obiectiv: Voce reală (>500ms) ar trebui să treacă

# Procedură:
# 1. Transmite voce normală (1-2 secunde)
# 2. Observă log SVXLink:

# Expected (SUCCES):
# - Vezi "Squelch opened" (OK)
# - Vezi audio flow în USRP packets
# - Vezi "Squelch closed" după ~1-2 secunde
# - Vezi "Valid transmission (1234ms) - forwarding to reflector"

# Dacă vocea NU e detectată (FAIL):
# - VOX_THRESH prea mare → reduce cu 500
# - SAU RXLevel prea scăzut în MMDVM → crește
```

**Test 4: Weak Signal Handling**

```bash
# Obiectiv: Semnal slab cu dropouts ar trebui să folosească extended hangtime

# Procedură:
# 1. Transmite de la distanță mare (siglev < 15)
# 2. Vorbește normal (siglev fluctuează)
# 3. Observă log SVXLink:

# Expected (SUCCES):
# - Vezi "Extended hangtime enabled" (când siglev < 15)
# - Squelch rămâne deschis prin dropouts scurte
# - Audio fără "pickling" (deschide-închide rapid)

# Dacă audio e choppy (FAIL):
# - SQL_EXTENDED_HANGTIME prea scurt → crește la 1500-2000ms
# - SAU SQL_EXTENDED_HANGTIME_THRESH prea scăzut → crește la 20
```

### 7.3 Tuning Iterativ

**Procedură Recommended:**

```
1. Start cu valori conservative:
   VOX_THRESH=3000
   SQL_HANGTIME=400
   MIN_TRANSMISSION_DURATION=500

2. Test kerchunk (quick key-up):
   → Dacă treace (BAD): VOX_THRESH += 500
   → Repetă până kerchunk e blocat

3. Test voce slabă:
   → Dacă NU detectează (BAD): VOX_THRESH -= 500
   → Găsește balance între false positives și false negatives

4. Test transmisii scurte (200-400ms):
   → Dacă trec (BAD): SQL_HANGTIME += 100
   → Repetă până transmisii scurte sunt blocate

5. Test voce normală (1-3 sec):
   → Dacă e blocată (BAD): SQL_HANGTIME -= 100
   → Găsește minimum hangtime care permite voce normală

6. Test semnal slab cu dropouts:
   → Dacă audio e choppy (BAD): SQL_EXTENDED_HANGTIME += 200
   → Ajustează până audio e smooth

7. Monitorizează statistici:
   → Target: >90% detectare corectă
   → False positives (zgomot ca voce): <5%
   → False negatives (voce ca zgomot): <5%
```

---

## 8. TROUBLESHOOTING

### 8.1 Problema: Kerchunk Trece Prin Filtru

**Simptome:**
- Quick key-up (50-100ms) deschide squelch
- Transmisii scurte (200-300ms) ajung la reflector

**Diagnostic:**
```bash
tail -f /var/log/svxlink.log

# Căută:
Squelch opened on Rx1 (siglev=XX)
Squelch closed on Rx1 (duration=123ms)
```

**Soluții:**

1. **Crește VOX_THRESH:**
   ```ini
   VOX_THRESH=4000  # În loc de 3000
   ```

2. **Crește SQL_HANGTIME:**
   ```ini
   SQL_HANGTIME=500  # În loc de 300-400
   ```

3. **Crește MIN_TRANSMISSION_DURATION:**
   ```ini
   MIN_TRANSMISSION_DURATION=600  # În loc de 500
   ```

4. **Adaugă SIGLEV filtering:**
   ```ini
   SQUELCH=COMBINE
   SQL_COMBINE=VOX AND SIGLEV
   SQL_SIGLEV_OPEN_THRESH=20  # Minimum siglev
   ```

### 8.2 Problema: Voce Reală NU E Detectată

**Simptome:**
- Transmiți voce, dar squelch NU se deschide
- SAU squelch se deschide, dar se închide imediat

**Diagnostic:**
```bash
# Verifică nivelul audio RX
tail -f /var/log/svxlink.log | grep -i "rms\|vox\|level"
```

**Soluții:**

1. **Reduce VOX_THRESH:**
   ```ini
   VOX_THRESH=2000  # În loc de 3000
   ```

2. **Crește RXLevel în MMDVM:**
   ```ini
   [Modem]
   RXLevel=60  # În loc de 50
   ```

3. **Crește preamp în svxlink.conf:**
   ```ini
   [Rx1]
   AUDIO_GAIN=+6  # +6dB boost
   ```

4. **Verifică discriminator output:**
   - Asigură-te că folosești discriminator output (unsquelched)
   - NU folosi audio squelched (silence când nu e semnal)

### 8.3 Problema: Audio Choppy (Pickling)

**Simptome:**
- Audio se deschide și închide rapid
- "Ppp-ppp-ppp" sound (multiple deschideri)

**Diagnostic:**
```bash
tail -f /var/log/svxlink.log | grep "Squelch"

# Vezi multe:
Squelch opened
Squelch closed (duration=50ms)
Squelch opened
Squelch closed (duration=30ms)
```

**Soluții:**

1. **Crește SQL_HANGTIME:**
   ```ini
   SQL_HANGTIME=600  # Mai lung hangtime
   ```

2. **Activează SQL_EXTENDED_HANGTIME:**
   ```ini
   SQL_EXTENDED_HANGTIME=1500
   SQL_EXTENDED_HANGTIME_THRESH=20  # Mai relaxat threshold
   ```

3. **Crește VOX_FILTER_DEPTH:**
   ```ini
   VOX_FILTER_DEPTH=400  # Rolling window mai lung
   ```

4. **Adaugă hysteresis în SIGLEV:**
   ```ini
   SQL_SIGLEV_OPEN_THRESH=18
   SQL_SIGLEV_CLOSE_THRESH=10  # Gap mare pentru hysteresis
   ```

### 8.4 Problema: Zgomot Local Detectat ca Voce

**Simptome:**
- Squelch se deschide fără transmisie RF
- Audio local (ventilator, zgomot echipament) trigger VOX

**Diagnostic:**
```bash
# Verifică dacă squelch se deschide fără RF
tail -f /var/log/svxlink.log

# Vezi:
Squelch opened (siglev=0)  # BAD - no RF!
```

**Soluții:**

1. **Folosește dual squelch (VOX AND SIGLEV):**
   ```ini
   SQUELCH=COMBINE
   SQL_COMBINE=VOX AND SIGLEV
   SQL_SIGLEV_OPEN_THRESH=15  # Minimum RF required
   ```

2. **Crește VOX_THRESH:**
   ```ini
   VOX_THRESH=4000  # Mai strict
   ```

3. **Reduce RXLevel în MMDVM (reduce zgomot local):**
   ```ini
   [Modem]
   RXLevel=40  # În loc de 50
   ```

4. **Îmbunătățește shield audio:**
   - Verifică cabluri audio (shield la ground)
   - Separă alimentare audio de alimentare digitală
   - Folosește filtru de zgomot (ferrite choke)

---

## CONCLUZIE

### Rezumat Configurare Anti-Kerchunk 90%+

**3 Parametri CRITICI:**

```ini
[Rx1]
# 1. ⭐ PRIMARY ANTI-KERCHUNK
SQL_HANGTIME=400              # 400ms eliminates <400ms transmissions

# 2. ⭐ VOICE DETECTION
VOX_THRESH=3000               # Tune pentru voce vs zgomot

# 3. ⭐ RF CONFIRMATION (dual squelch)
SQUELCH=COMBINE
SQL_COMBINE=VOX AND SIGLEV
SQL_SIGLEV_OPEN_THRESH=18     # Minimum RF level
```

**Custom Code în UsrpLogic:**

```cpp
// ⭐ MINIMUM DURATION CHECK
if (transmission_duration < MIN_TRANSMISSION_DURATION) {
  log("Kerchunk blocked: " + duration + "ms < 500ms");
  return;  // NU transmite la reflector
}
```

**Rezultat Așteptat:**

| Tip Transmisie | Durata | Voce | RF | Rezultat |
|----------------|--------|------|----|----|
| Kerchunk pur | 50-100ms | ❌ | ✅ | ❌ BLOCAT (sub VOX_THRESH) |
| Quick modulation | 200-300ms | ❌ | ✅ | ❌ BLOCAT (sub SQL_HANGTIME) |
| Test rapid | 400-500ms | ✅ | ✅ | ⚠️ LIMITĂ (ajustabil) |
| Voce normală | >500ms | ✅ | ✅ | ✅ TRANSMIS |
| Zgomot local | orice | ✅ | ❌ | ❌ BLOCAT (dual squelch) |

**Acuratețe: >90% cu tuning corect!** 🎯
