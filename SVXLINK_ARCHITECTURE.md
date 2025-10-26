# SVXLINK ARCHITECTURE - COMPLETE ANALYSIS

## Overview
SVXLink is a sophisticated multi-purpose voice services system for ham radio, built on an event-driven asynchronous architecture. This document provides a comprehensive analysis of the core architecture, USRP protocol integration, and MMDVM digital voice support.

**Analysis Date:** 2025-10-26
**Branch:** svxlink-usrp
**Repository:** /private/tmp/svxlink

---

## TABLE OF CONTENTS

1. [Core Architecture](#1-core-architecture)
2. [Audio Architecture (Async Library)](#2-audio-architecture-async-library)
3. [USRP Protocol Integration](#3-usrp-protocol-integration)
4. [MMDVM / Digital Voice Integration](#4-mmdvm--digital-voice-integration)
5. [UsrpLogic Audio Flow](#5-usrplogic-audio-flow)
6. [External Codec Integration](#6-external-codec-integration)
7. [Configuration](#7-configuration)
8. [Key Implementation Files](#8-key-implementation-files)
9. [Protocol Sequence Diagrams](#9-protocol-sequence-diagrams)
10. [Design Patterns](#10-design-patterns)
11. [Critical Design Principles](#11-critical-design-principles)
12. [MMDVM Integration Summary](#12-mmdvm-integration-summary)
13. [Limitations & Notes](#13-limitations--notes)
14. [References](#14-references)

---

## 1. CORE ARCHITECTURE

### 1.1 Application Framework

**Base:** `Async::CppApplication` (`src/async/cpp/AsyncCppApplication.h`)
- Single-threaded event loop using `select()` for non-blocking I/O
- No mutex locks needed (entire app runs in one thread)
- Excellent for real-time audio processing
- Signal handling: SIGTERM, SIGINT, SIGHUP
- Manages timers, file descriptors, DNS lookups

**Main Entry:** `src/svxlink/svxlink/svxlink.cpp`
- Loads configuration from INI files
- Creates Logic instances (Simplex, Repeater, Reflector)
- Runs main event loop

### 1.2 Logic Core Hierarchy

```
Async::CppApplication (Event Loop)
  └─> LogicBase
      ├─> SimplexLogic (single frequency)
      ├─> RepeaterLogic (duplex with timing)
      ├─> ReflectorLogic (V1 protocol server)
      ├─> ReflectorV2Logic (V2 protocol server)
      ├─> UsrpLogic (USRP/MMDVM integration) ⭐
      └─> DummyLogic (test/demo)
```

**Logic Components** (`src/svxlink/svxlink/Logic.h`):
```
Logic {
  Rx* m_rx                      // Receiver instance
  Tx* m_tx                      // Transmitter instance
  Module* active_module         // Currently active module
  MsgHandler* msg_handler       // Message playback
  EventHandler* event_handler   // TCL event interpreter
  QsoRecorder* qso_recorder     // QSO recording

  Audio Pipeline:
  ├─ AudioMixer* tx_audio_mixer
  ├─ AudioSelector* tx_audio_selector
  ├─ AudioAmp* fx_gain_ctrl
  ├─ AudioSplitter* rx_splitter
  ├─ AudioValve* rx_valve
  └─ AudioStreamStateDetector* state_det
}
```

### 1.3 Event System (TCL Integration)

**EventHandler** (`EventHandler.h`):
- Manages TCL interpreter instance
- Executes callbacks on events:
  - `squelchOpen(bool)`
  - `dtmfDigitDetected(char, int)`
  - `audioStreamStateChange(bool, bool)`
  - `transmitterStateChange(bool)`
  - `allMsgsWritten()`
  - `talkerInfo(string, string)`

**Event Flow:**
```
Hardware Event (Rx squelch)
  → Rx::squelchOpen() signal
  → Logic::squelchOpen(bool)
  → EventHandler::processEvent()
  → TCL callback (*.tcl config)
  → Module activation / Message playback
```

---

## 2. AUDIO ARCHITECTURE (Async Library)

### 2.1 Core Audio Classes (`src/async/audio/`)

**Pull-Push Model:**
- `AsyncAudioSource.h` - Base class for audio producers
  - Methods: `registerSink()`, `sinkWriteSamples()`, `sinkFlushSamples()`
  - Handlers: `resumeOutput()`, `allSamplesFlushed()`

- `AsyncAudioSink.h` - Base class for audio consumers
  - Methods: `registerSource()`, `consumeSamples()`
  - Backpressure handling via managed sinks

### 2.2 Audio Pipeline Components

**Mixing & Routing:**
- `AudioMixer` - Combines multiple audio sources
- `AudioSelector` - Routes one of many inputs to output
- `AudioSplitter` - Duplicates stream to multiple sinks
- `AudioValve` - Gate control (open/close flow)

**Processing:**
- `AudioCompressor` - Dynamic range compression
- `AudioClipper` - Prevents clipping with limiting
- `AudioFilter` - FIR/IIR filtering
- `AudioAmp` - Gain amplification
- `AudioDelayLine` - Time-domain delay

**Sample Rate Conversion:**
- `AudioInterpolator` - Upsampling (increases sample rate)
- `AudioDecimator` - Downsampling (decreases sample rate)
- Uses high-quality FIR filters (`multirate_filter_coeff.h`)

**Buffering & Jitter:**
- `AudioFifo` - Standard FIFO buffer
- `AudioJitterFifo` ⭐ - **Jitter-tolerant buffer** (DO NOT TOUCH)
  - Handles variable packet arrival
  - Adaptive to V1 (60ms) and V2 (20ms) protocols
  - Battle-tested from SVXLink design
- `AudioPacer` - Timing control/pacing

**Codec Support:**
- Encoders: `AudioEncoder*` (Opus, Speex, GSM, Raw, S16)
- Decoders: `AudioDecoder*` (Opus, Speex, GSM, Raw, S16)
- Containers: `AudioContainer*` (WAV, PCM, Opus)

### 2.3 Sample Rate Architecture

**Operating Points:**
- Opus: 16kHz native (no upsampling/downsampling at codec level)
- USRP Protocol: 8kHz (160 samples/20ms frames)
- Hardware: Typically 48kHz or 44.1kHz
- DTMF decoding: 8-16kHz

**Conversion Flow:**
```
Hardware (48kHz)
  → AudioDecimator (↓6)
  → 8kHz (USRP protocol layer)
  → AudioInterpolator (↑6)
  → 48kHz (Hardware output)
```

---

## 3. USRP PROTOCOL INTEGRATION

### 3.1 Protocol Overview

**USRP Protocol** (`src/svxlink/svxlink/contrib/UsrpLogic/usrp_protocol.txt`):
- Originally from AllStar (2010, KA1RBI)
- Used by: MMDVMHost, USRP2M17, Analog_Bridge, Analog_Reflector
- Transport: UDP/IP
- Purpose: Analog audio + digital voice metadata exchange

**Frame Structure:**
```
[32-byte Header] + [Variable Data]

Header Layout:
Bytes  0-3:   "USRP" identifier (ASCII)
Bytes  4-7:   Sequence number (little-endian)
Bytes  8-11:  Memory (unused, set to 0)
Bytes 12-15:  PTT status (byte 15: 1=ON, 0=OFF)
Bytes 16-19:  Talkgroup (unused, set to 0)
Bytes 20-23:  Frame Type (byte 20: type value)
Bytes 24-27:  Mpxid (unused, set to 0)
Bytes 28-31:  Reserved (unused, set to 0)
```

### 3.2 Frame Types (`UsrpMsg.h:97-105`)

```cpp
USRP_TYPE_VOICE      = 0  // Audio data (160 samples @ 8kHz)
USRP_TYPE_DTMF       = 1  // DTMF data / Commands
USRP_TYPE_TEXT       = 2  // Metadata (JSON or TLV)
USRP_TYPE_PING       = 3  // Heartbeat/ping
USRP_TYPE_TLV        = 4  // TLV-tagged metadata
USRP_TYPE_VOICE_ADPCM= 5  // ADPCM-compressed audio
USRP_TYPE_VOICE_ULAW = 6  // ULAW-compressed audio
```

### 3.3 TLV Tags (Type-Length-Value) (`UsrpMsg.h:101-105`)

```cpp
TLV_TAG_BEGIN_TX  = 0
TLV_TAG_AMBE      = 1  // AMBE codec data
TLV_TAG_END_TX    = 2
TLV_TAG_TG_TUNE   = 3  // Talkgroup tuning
TLV_TAG_PLAY_AMBE = 4
TLV_TAG_REMOTE_CMD= 5
TLV_TAG_AMBE_49   = 6  // AMBE @ 49bit/frame
TLV_TAG_AMBE_72   = 7  // AMBE @ 72bit/frame
TLV_TAG_SET_INFO  = 8  // Digital mode metadata ⭐
TLV_TAG_IMBE      = 9  // IMBE codec data (P25)
TLV_TAG_DSAMBE    = 10 // D-STAR AMBE
TLV_TAG_FILE_XFER = 11
```

### 3.4 Audio Frame Format

**Voice Frame** (USRP_TYPE_VOICE = 0):
```
PTT Status: 1 (ON) for audio, 0 (OFF) for last frame
Data: 160 16-bit signed PCM samples @ 8000 Hz
Encoding: Little-endian
Frame Duration: 20ms (160 samples ÷ 8000 Hz)
Total Size: 32 bytes header + 320 bytes audio = 352 bytes
```

**UsrpAudioMsg Class** (`UsrpMsg.h:123-182`):
```cpp
class UsrpAudioMsg : public Async::Msg {
  uint32_t m_seq;                        // Sequence number
  uint32_t m_keyup;                      // PTT on/off
  uint32_t m_type;                       // Frame type
  std::array<int16_t, 160> m_audio_data; // 160 samples

  void setAudioData(int16_t in[160]);
  void setKeyup(bool keyup);
  void setSeq(uint32_t seq);
};
```

---

## 4. MMDVM / DIGITAL VOICE INTEGRATION

### 4.1 Digital Voice Modes

**Supported via USRP Protocol:**
```cpp
MODE_NONE = 0
MODE_DMR  = 1  // Digital Mobile Radio
MODE_P25  = 2  // Project 25
MODE_NXDN = 3  // Next eXtension Node

const std::string selected_mode[] = {
  "*NONE", "*DMR", "*P25", "*NXDN"
};
```

**Additional Modes (in protocol spec):**
- YSF (System Fusion)
- D-STAR (via DSAMBE)

### 4.2 Mode Switching

**Function:** `UsrpLogic::switchMode()` (`UsrpLogic.cpp:1030-1057`)

```cpp
void UsrpLogic::switchMode(uint8_t mode) {
  UsrpTlvMetaMsg usrp;
  usrp.setMetaData(selected_mode[mode]); // "*DMR", "*P25", "*NXDN"
  usrp.setType(USRP_TYPE_DTMF);          // Type = 1
  usrp.setTlv(0x00);
  usrp.setTlvLen(0x00);
  usrp.setSeq(udp_seq++);

  // Send via UDP
  ostringstream os;
  usrp.pack(os);
  sendUdpMessage(os);

  // Trigger TCL event
  processEvent("switch_to_mode " + selected_mode[mode]);
}
```

**Protocol Flow:**
```
SVXLink → UDP USRP_TYPE_DTMF frame with "*DMR" string
  ↓
Analog_Bridge / MMDVMHost receives
  ↓
Switches AMBE codec mode
  ↓
Sends back USRP_TYPE_TEXT with "INFO:MSG:Setting mode to DMR"
```

### 4.3 Digital Metadata Structure

**TLV Metadata** (`UsrpTlvMetaMsg` class, `UsrpMsg.h:322-495`):

```cpp
class UsrpTlvMetaMsg : public Async::Msg {
  uint8_t  m_tlv;                    // TLV tag (0x08 = SET_INFO)
  uint8_t  m_tlvlen;                 // Metadata length
  std::array<uint8_t, 3> m_dmrid;    // DMR ID (3 bytes)
  uint32_t m_rptid;                  // Repeater ID (4 bytes)
  std::array<uint8_t, 3> m_tg;       // Talkgroup (3 bytes)
  uint8_t  m_ts;                     // Timeslot (1 byte)
  uint8_t  m_cc;                     // Color Code (1 byte)
  std::array<uint8_t, 306> m_meta;   // Callsign + padding

  // Methods:
  void setDmrId(uint32_t dmrid);
  void setRptId(uint32_t rptid);
  void setTg(uint32_t tg);
  void setCC(uint8_t cc);  // Color Code (DMR)
  void setTS(uint8_t ts);  // Timeslot 1-2 (DMR)
  void setCallsign(std::string call);
};
```

**Metadata Binary Layout:**
```
TLV Tag (1 byte): 0x08 (TLV_TAG_SET_INFO)
TLV Length (1 byte): 13 + len(callsign)
DMR ID (3 bytes): Big-endian
Repeater ID (4 bytes): Little-endian
Talkgroup (3 bytes): Big-endian
Timeslot (1 byte): 1-4
Color Code (1 byte): 0-15
Callsign (variable): ASCII, max 306 bytes
Padding: 0x00
```

### 4.4 JSON Metadata (from Analog_Bridge)

**JSON Structure** (`usrp_metadata_json.txt`):

```json
{
  "ab": {
    "version": "1.6.2",
    "date": "Wed.Mar.31.13:52:10.EDT.2021"
  },
  "dv3000": {
    "ip": "127.0.0.1",
    "port": "2460",
    "use_serial": "false"
  },
  "tlv": {
    "ip": "127.0.0.1",
    "ambe_size": "72",
    "ambe_mode": "NXDN"
  },
  "digital": {
    "gw": "1234567",      // Gateway DMR ID
    "rpt": "123456789",   // Repeater ID
    "tg": "7",            // Talkgroup
    "ts": "2",            // Timeslot
    "cc": "1",            // Color Code
    "call": "N0CALL"      // Callsign
  },
  "last_tune": "7"
}
```

**JSON Parsing** (`UsrpLogic.cpp:704-716`):
```cpp
m_last_call = value["digital"]["call"].asString();
m_last_tg = atoi(value["digital"]["tg"].asString().c_str());
m_last_dmrid = atoi(value["digital"]["rpt"].asString().c_str());
m_last_ts = atoi(value["digital"]["ts"].asString().c_str());
m_last_cc = atoi(value["digital"]["cc"].asString().c_str());
m_last_mode = value["tlv"]["ambe_mode"].asString();
```

---

## 5. USRPLOGIC AUDIO FLOW

### 5.1 TX Path (Local → Network)

**Audio Processing Chain** (`UsrpLogic.cpp:289-397`):

```
Logic Audio Input (16kHz internal)
  ↓
m_logic_con_in (AudioStreamStateDetector)
  ↓
Preamp (optional, configurable -20dB to +20dB)
  ↓
AudioFilter (FILTER_TO_USRP, e.g., "BpBu1/600-3500")
  ↓
AudioDecimator (16kHz → 8kHz for USRP)
  ↓
AudioCompressor (LOCAL_LIMITER_THRESH, e.g., -6.0 dBFS)
  ↓
AudioClipper (hard limiting)
  ↓
AudioEncoder (S16 = raw PCM 16-bit)
  ↓
sendEncodedAudio() - Buffer to 160 samples
  ↓
UsrpAudioMsg (PTT=1, Type=VOICE, seq++, 160 samples)
  ↓
UDP sendto(USRP_HOST:USRP_TX_PORT)
```

**Key Functions:**

1. **sendEncodedAudio()** (`UsrpLogic.cpp:531-563`):
```cpp
void UsrpLogic::sendEncodedAudio(const void *buf, int count) {
  // First frame: send metadata
  if (!ident) {
    sendMetaMsg();
  }

  // Accumulate samples to 160 (20ms @ 8kHz)
  memcpy(r_buf + stored_samples, buf, sizeof(int16_t) * len);
  stored_samples += len;

  // Send complete frames
  while (stored_samples >= USRP_AUDIO_FRAME_LEN) {
    usrp.setAudioData(r_buf);
    usrp.setType(USRP_TYPE_VOICE);
    usrp.setKeyup(true);
    sendAudioMsg(usrp);

    // Shift buffer
    memmove(r_buf, r_buf + 160, ...);
    stored_samples -= 160;
  }
}
```

2. **sendMetaMsg()** (`UsrpLogic.cpp:863-900`):
```cpp
void UsrpLogic::sendMetaMsg(void) {
  UsrpTlvMetaMsg usrp;
  usrp.setTg(m_selected_tg);        // Talkgroup
  usrp.setRptId(m_rptid);           // Repeater ID
  usrp.setCC(m_selected_cc);        // Color Code (DMR)
  usrp.setTS(m_selected_ts);        // Timeslot (DMR)
  usrp.setCallsign(m_callsign);     // Callsign
  usrp.setDmrId(m_dmrid);           // DMR ID

  sendUdpMessage(os);
  processEvent("transmission_start " + m_selected_tg);
}
```

3. **sendStopMsg()** (`UsrpLogic.cpp:838-860`):
```cpp
void UsrpLogic::sendStopMsg(void) {
  UsrpHeaderMsg usrp;
  usrp.setSeq(++udp_seq);
  usrp.setKeyup(false); // PTT OFF

  sendUdpMessage(os);
  processEvent("transmission_stop " + m_selected_tg);
}
```

**TX Latency:** ~5-10ms (decimation + buffering + encoding)

### 5.2 RX Path (Network → Local)

**Audio Processing Chain** (`UsrpLogic.cpp:363-397`):

```
UDP receive (USRP_RX_PORT)
  ↓
udpDatagramReceived() - Parse USRP frame
  ↓
handleVoiceStream() - Extract 160 samples @ 8kHz
  ↓
AudioDecoder (S16 = raw PCM 16-bit)
  ↓
AudioFilter (FILTER_FROM_USRP, e.g., "HsBq2/0.01/-18/4000")
  ↓
AudioInterpolator (8kHz → 16kHz internal)
  ↓
Net Preamp (optional, NET_PREAMP)
  ↓
AudioCompressor (NET_LIMITER_THRESH)
  ↓
AudioClipper (hard limiting)
  ↓
m_logic_con_out (AudioStreamStateDetector)
  ↓
Logic Audio Output (16kHz internal)
```

**Key Functions:**

1. **udpDatagramReceived()** (`UsrpLogic.cpp:573-739`):
```cpp
void UsrpLogic::udpDatagramReceived(const IpAddress& addr,
                                     uint16_t port,
                                     void *buf, int count) {
  UsrpHeaderMsg usrp;
  usrp.unpack(si);

  uint32_t utype = usrp.type();

  if (utype == USRP_TYPE_VOICE) {
    if (usrp.keyup() == false) {
      handleStreamStop();  // PTT OFF
    } else {
      UsrpAudioMsg usrpaudio;
      usrpaudio.unpack(si);
      handleVoiceStream(usrpaudio);
    }
  }
  else if (utype == USRP_TYPE_TEXT) {
    // Parse TLV or JSON metadata
    // Extract callsign, TG, DMR ID, mode
    processEvent("usrp_stationdata_received ...");
  }
}
```

2. **handleVoiceStream()** (`UsrpLogic.cpp:742-752`):
```cpp
void UsrpLogic::handleVoiceStream(UsrpAudioMsg usrp) {
  gettimeofday(&m_last_talker_timestamp, NULL);

  // Network byte order → host byte order
  std::array<int16_t, 160> m_audio_data;
  for (size_t i = 0; i < 160; i++) {
    m_audio_data[i] = ntohs(usrp.audioData()[i]);
  }

  // Feed to decoder
  m_dec->writeEncodedSamples(&m_audio_data,
                             sizeof(int16_t) * 160);
}
```

3. **handleStreamStop()** (`UsrpLogic.cpp:755-765`):
```cpp
void UsrpLogic::handleStreamStop(void) {
  m_dec->flushEncodedSamples();
  checkIdle();
  m_enc->allEncodedSamplesFlushed();
  timerclear(&m_last_talker_timestamp);

  processEvent("talker_stop " + m_last_tg + " " + m_last_call);
}
```

**RX Latency:** ~5-10ms (decoding + interpolation)

### 5.3 Stream State Management

**PTT Control via Audio Stream State:**

1. **TX State Change** (`UsrpLogic.cpp:1000-1008`):
```cpp
void UsrpLogic::onLogicConInStreamStateChanged(bool is_active,
                                                bool is_idle) {
  checkIdle();
  if (is_idle) {
    sendStopMsg();  // Send PTT OFF frame
  }
}
```

2. **Idle Detection** (`UsrpLogic.cpp:1018-1027`):
```cpp
bool UsrpLogic::isIdle(void) {
  return m_logic_con_out->isIdle() &&
         m_logic_con_in->isIdle();
}

void UsrpLogic::checkIdle(void) {
  setIdle(isIdle());
}
```

3. **Timeout Handling** (`UsrpLogic.cpp:935-949`):
```cpp
void UsrpLogic::handleTimerTick(Async::Timer *t) {
  if (timerisset(&m_last_talker_timestamp)) {
    struct timeval now, diff;
    gettimeofday(&now, NULL);
    timersub(&now, &m_last_talker_timestamp, &diff);

    // 3 second timeout
    if (diff.tv_sec > 3) {
      log(LOGINFO, "Last talker audio timeout");
      m_dec->flushEncodedSamples();
      timerclear(&m_last_talker_timestamp);
    }
  }
}
```

---

## 6. EXTERNAL CODEC INTEGRATION

### 6.1 AMBE Codec Architecture

**SVXLink does NOT include AMBE codec** (proprietary).

Instead, it uses the USRP protocol to communicate with external transcoding services:

1. **DV3000 USB Hardware Transcoder**
   - AMBE+2 vocoder hardware
   - IP or serial connection
   - Configuration in JSON metadata

2. **md380-emu Service**
   - Software-based AMBE emulator
   - Network-based interface
   - Open-source alternative

**Codec Configuration** (from JSON metadata):
```json
"dv3000": {
  "ip": "127.0.0.1",
  "port": "2460",
  "use_serial": "false"
},
"tlv": {
  "ip": "127.0.0.1",
  "ambe_size": "72",     // AMBE frame size in bits
  "ambe_mode": "NXDN"    // Current mode
}
```

### 6.2 Codec Data Flow

**Digital Voice TX Path:**
```
SVXLink Audio (8kHz PCM)
  → USRP Protocol (USRP_TYPE_VOICE)
  → Analog_Bridge
  → DV3000 / md380-emu
  → AMBE encoding
  → MMDVMHost
  → RF Modulator / Digital Network
```

**Digital Voice RX Path:**
```
RF Demodulator / Digital Network
  → MMDVMHost
  → AMBE frames
  → DV3000 / md380-emu
  → AMBE decoding
  → Analog_Bridge
  → USRP Protocol (USRP_TYPE_VOICE)
  → SVXLink Audio (8kHz PCM)
```

---

## 7. CONFIGURATION

### 7.1 UsrpLogic Configuration (`UsrpLogic.conf`)

```ini
[UsrpLogic]
TYPE=Usrp                        # Logic type
CALL=N0CALL                      # Callsign (max 6 chars)

# Network Settings
USRP_HOST=127.0.0.1              # Analog_Bridge host
USRP_TX_PORT=41234               # TX port
USRP_RX_PORT=41233               # RX port

# Digital Voice Parameters
DMRID=1234567                    # Your DMR ID
RPTID=123456789                  # Repeater ID
DEFAULT_TG=9                     # Default talkgroup
DEFAULT_CC=1                     # Color Code (DMR)
DEFAULT_TS=1                     # Timeslot 1-2 (DMR)

# Audio Processing
PREAMP=0                         # TX gain in dB (-20 to +20)
NET_PREAMP=0                     # RX gain in dB (-20 to +20)
FILTER_TO_USRP=BpBu1/600-3500    # TX bandpass filter
FILTER_FROM_USRP=HsBq2/0.01/-18/4000  # RX highshelf filter

# Dynamics Processing
LOCAL_LIMITER_THRESH=-6.0        # TX compression (dBFS)
NET_LIMITER_THRESH=-6.0          # RX compression (dBFS)
JITTER_BUFFER_DELAY=400          # RX jitter buffer (ms)

# User Database
DV_USER_INFOFILE=/etc/svxlink/dv_users.json
SHARE_USERINFO=1

# Debugging
DEBUG=0                          # 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG
```

### 7.2 Filter Specifications

**Filter Syntax:**
```
Type[Order]/Frequency1[-Frequency2]

Types:
- Lp = Lowpass
- Hp = Highpass
- Bp = Bandpass
- Bs = Bandstop
- Hs = Highshelf
- Ls = Lowshelf

Filter Families:
- Bu = Butterworth
- Ch = Chebyshev
- Bq = Biquad

Examples:
- "LpBu4/3000"         → 4th-order Butterworth lowpass @ 3kHz
- "BpBu1/600-3500"     → 1st-order Butterworth bandpass 600Hz-3.5kHz
- "HsBq2/0.01/-18/4000"→ 2nd-order Biquad highshelf, Q=0.01, -18dB, 4kHz
```

### 7.3 Digital Voice User Database

**dv_users.json Structure:**
```json
[
  {
    "id": "2620055",
    "mode": "DMR",
    "name": "Adi",
    "call": "DL1HRC-1",
    "location": "Leuna",
    "symbol": "\\r",
    "comment": "DMR ID"
  },
  {
    "id": "9031",
    "mode": "NXDN",
    "name": "Adi",
    "call": "DL1HRC-2",
    "location": "Leuna",
    "symbol": "\\r",
    "comment": "SvxLink Sysop"
  }
]
```

---

## 8. KEY IMPLEMENTATION FILES

### 8.1 UsrpLogic Module

| File | Lines | Purpose |
|------|-------|---------|
| `UsrpMsg.h` | 502 | Protocol message definitions (3 classes) |
| `UsrpLogic.h` | 279 | Logic class header, public interface |
| `UsrpLogic.cpp` | 1221 | Main implementation (audio, metadata, control) |
| `usrp_protocol.txt` | 310 | USRP protocol specification |
| `usrp_metadata_json.txt` | 15 | JSON metadata example |
| `UsrpLogic.conf.5` | 108 | Configuration manual page |
| `UsrpLogic.conf.in` | 22 | Default configuration template |

**Location:** `src/svxlink/svxlink/contrib/UsrpLogic/`

### 8.2 Async Audio Library

| Component | Files | Purpose |
|-----------|-------|---------|
| Core | `AsyncAudioSource.h`, `AsyncAudioSink.h` | Base classes |
| Processing | `AsyncAudioAmp.h`, `AsyncAudioFilter.h`, `AsyncAudioCompressor.h`, `AsyncAudioClipper.h` | DSP |
| SRC | `AsyncAudioInterpolator.h`, `AsyncAudioDecimator.h` | Sample rate conversion |
| Buffering | `AsyncAudioFifo.h`, `AsyncAudioJitterFifo.h` | Buffers |
| Codecs | `AsyncAudioEncoder*.h`, `AsyncAudioDecoder*.h` | Codecs |
| Routing | `AsyncAudioMixer.h`, `AsyncAudioSplitter.h`, `AsyncAudioSelector.h`, `AsyncAudioValve.h` | Routing |

**Location:** `src/async/audio/`

---

## 9. PROTOCOL SEQUENCE DIAGRAMS

### 9.1 Digital Voice Transmission

```
SVXLink                  Analog_Bridge           MMDVMHost
   |                           |                      |
   |---USRP_TYPE_TEXT--------->|                      |
   |   (TLV metadata:          |                      |
   |    TG, DMR ID, Call)      |                      |
   |                           |                      |
   |---USRP_TYPE_VOICE-------->|                      |
   |   (PTT=1, 160 samples)    |                      |
   |                           |---AMBE frames------->|
   |                           |                      |---RF TX--->
   |                           |                      |
   |---USRP_TYPE_VOICE-------->|                      |
   |   (PTT=1, 160 samples)    |                      |
   |   ...                     |---AMBE frames------->|
   |                           |                      |
   |---USRP_TYPE_VOICE-------->|                      |
   |   (PTT=0, last frame)     |                      |
   |                           |---AMBE END---------->|
   |                           |                      |---RF END-->
```

### 9.2 Digital Voice Reception

```
SVXLink                  Analog_Bridge           MMDVMHost
   |                           |                      |
   |                           |                      |<--RF RX---
   |                           |<--AMBE frames--------|
   |<--USRP_TYPE_TEXT----------|                      |
   |   (JSON metadata:         |                      |
   |    TG, DMR ID, Call, Mode)|                      |
   |                           |                      |
   |<--USRP_TYPE_VOICE---------|                      |
   |   (PTT=1, 160 samples)    |                      |
   |                           |                      |
   |<--USRP_TYPE_VOICE---------|                      |
   |   (PTT=1, 160 samples)    |                      |
   |   ...                     |                      |
   |                           |                      |
   |<--USRP_TYPE_VOICE---------|                      |
   |   (PTT=0, last frame)     |                      |
```

### 9.3 Mode Switching

```
SVXLink                  Analog_Bridge
   |                           |
   |---USRP_TYPE_DTMF--------->|
   |   (data = "*DMR")         |
   |                           |---(Switch AMBE mode to DMR)
   |                           |
   |<--USRP_TYPE_TEXT----------|
   |   (data = "INFO:MSG:      |
   |    Setting mode to DMR")  |
   |                           |
   |---(processEvent:          |
   |     "setting_mode DMR")   |
```

---

## 10. DESIGN PATTERNS

### 10.1 Observer Pattern (sigc++)

**Signal/Slot System:**
```cpp
// Signal declaration
sigc::signal<void, bool> squelchOpen;

// Connection
squelchOpen.connect(
  sigc::mem_fun(*this, &Logic::onSquelchOpen)
);

// Emission
squelchOpen(true);
```

**Used Throughout:**
- Audio pipeline connections
- Event callbacks
- State change notifications

### 10.2 Factory Pattern

**AudioDeviceFactory:**
```cpp
AudioDevice* AudioDeviceFactory::create(const std::string& type);
// Returns: AudioDeviceAlsa, AudioDeviceOSS, AudioDeviceUDP, etc.
```

**AudioEncoder/Decoder Factory:**
```cpp
AudioEncoder* AudioEncoder::create(const std::string& name);
// Returns: AudioEncoderOpus, AudioEncoderS16, AudioEncoderGsm, etc.

AudioDecoder* AudioDecoder::create(const std::string& name);
// Returns: AudioDecoderOpus, AudioDecoderS16, AudioDecoderGsm, etc.
```

### 10.3 Plugin Pattern

**Dynamic Module Loading:**
```cpp
extern "C" {
  LogicBase* construct(void) {
    return new UsrpLogic;
  }
}
```

- Modules loaded via `dlopen()`
- Implement standard `LogicBase` interface
- Config-driven activation

### 10.4 Strategy Pattern

**Swappable Implementations:**
- DTMF decoders (Software, Hardware, S54S, Span, etc.)
- Signal level detectors (AFSK, DDR, Tone, Noise, etc.)
- Squelch algorithms (SigLev, CTCSS, VOX, Combined)
- Audio devices (ALSA, OSS, UDP)

---

## 11. CRITICAL DESIGN PRINCIPLES

### 11.1 Single-Threaded Event Loop

**Advantages:**
- No mutex locks needed
- No race conditions
- Deterministic execution
- Excellent for real-time audio

**Implementation:**
- All I/O via `select()` on file descriptors
- Timers managed in single queue
- Callbacks execute in main thread
- Audio processing in callbacks (low latency)

### 11.2 Pull-Push Audio Architecture

**Pull Model (AudioSource → AudioSink):**
```
AudioSource produces samples
  → calls sinkWriteSamples() on registered sinks
  → AudioSink consumes samples via consumeSamples()
  → returns number of samples consumed
  → AudioSource manages backpressure
```

**Advantages:**
- Natural backpressure handling
- No buffering needed at source
- Consumer controls flow rate
- Works perfectly with event loop

### 11.3 Non-Blocking I/O

**All I/O Operations:**
- UDP sockets: Non-blocking send/receive
- File I/O: Handled via `AsyncFile` with select()
- Serial ports: Non-blocking via termios
- Audio devices: Non-blocking or small buffers

**Timeout Handling:**
- Timers for activity detection
- Watchdogs for stuck states
- Graceful degradation on errors

---

## 12. MMDVM INTEGRATION SUMMARY

### 12.1 What UsrpLogic Provides

✅ **Analog-to-Digital Bridge:**
- Converts SVXLink analog audio (8kHz PCM) to USRP protocol
- Converts USRP protocol to SVXLink analog audio
- Passes digital voice metadata (TG, DMR ID, Callsign)
- Supports mode switching (DMR, P25, NXDN, YSF)

✅ **NOT Included:**
- AMBE codec (outsourced to DV3000 or md380-emu)
- DMR protocol handling (done by MMDVMHost)
- RF modulation/demodulation (done by MMDVM hardware)
- Network protocols (DMRplus, BrandMeister, etc. - handled by MMDVMHost)

### 12.2 Typical MMDVM Setup

```
┌──────────────┐
│  SVXLink     │
│  UsrpLogic   │  8kHz PCM audio
│              │◄──────────────────┐
└──────────────┘                   │
        │                          │
        │ UDP USRP Protocol        │
        │ (8kHz PCM + metadata)    │
        ▼                          │
┌──────────────┐                   │
│ Analog_Bridge│  AMBE frames      │
│              │◄────────────┐     │
└──────────────┘             │     │
        │                    │     │
        │ AMBE codec via:    │     │
        │ - DV3000 (USB)     │     │
        │ - md380-emu (SW)   │     │
        ▼                    │     │
┌──────────────┐             │     │
│  MMDVMHost   │             │     │
│              ├─────────────┘     │
└──────────────┘                   │
        │                          │
        │ Serial                   │
        ▼                          │
┌──────────────┐                   │
│ MMDVM Modem  │                   │
│  (Hardware)  │                   │
└──────────────┘                   │
        │                          │
        │ RF (DMR/P25/NXDN)        │
        ▼                          │
    Antenna ──────────────────────┘
```

### 12.3 Audio Sample Rates

| Component | Sample Rate | Format | Notes |
|-----------|-------------|--------|-------|
| SVXLink internal | 16kHz | float | Native processing rate |
| USRP protocol | 8kHz | int16_t | 160 samples/20ms frames |
| AMBE codec | 8kHz | AMBE frames | 72-bit or 49-bit per 20ms |
| DMR RF | 8kHz | 4FSK modulated | Air interface |

**Sample Rate Conversions:**
```
SVXLink TX:
  16kHz (internal) → Decimator → 8kHz (USRP) → Analog_Bridge

SVXLink RX:
  Analog_Bridge → 8kHz (USRP) → Interpolator → 16kHz (internal)
```

---

## 13. LIMITATIONS & NOTES

### 13.1 Current Limitations

1. **No Native AMBE Codec:**
   - SVXLink does NOT include AMBE codec (proprietary)
   - Requires external transcoding service (DV3000, md380-emu)
   - Adds latency (typically 10-20ms)

2. **USRP Protocol Transport:**
   - UDP only (no serial support in UsrpLogic)
   - Requires network stack overhead
   - Cannot talk directly to MMDVM serial port

3. **Sample Rate:**
   - USRP protocol fixed at 8kHz
   - Requires sample rate conversion in SVXLink
   - Additional latency from decimation/interpolation

4. **No Direct Digital Mode Control:**
   - Cannot control MMDVM modem directly
   - All digital mode commands go through Analog_Bridge
   - Limited to modes supported by MMDVMHost

### 13.2 Best Practices

✅ **DO:**
- Use high-quality audio filters (configure FILTER_TO_USRP, FILTER_FROM_USRP)
- Set appropriate limiter thresholds (LOCAL_LIMITER_THRESH, NET_LIMITER_THRESH)
- Monitor audio levels via VU meters
- Use jitter buffer (JITTER_BUFFER_DELAY=400ms recommended)
- Keep UDP sequence numbers (auto-handled)
- Send metadata before first audio frame (auto-handled)

❌ **DON'T:**
- Modify AudioJitterFifo (battle-tested, complex timing logic)
- Use preamp > +10dB (risk of clipping)
- Set limiter threshold > -1dB (risk of distortion)
- Disable jitter buffer (causes audio dropouts)
- Mix different audio sample rates (use SRC)

### 13.3 Troubleshooting

**No Audio TX:**
- Check USRP_HOST, USRP_TX_PORT configuration
- Verify Analog_Bridge is running and listening
- Check firewall rules (UDP ports)
- Enable DEBUG=3 to see packet transmission
- Verify FILTER_TO_USRP is not too aggressive

**No Audio RX:**
- Check USRP_RX_PORT is correct (different from TX port!)
- Verify SVXLink is listening on correct interface
- Check JITTER_BUFFER_DELAY (try increasing if choppy)
- Verify FILTER_FROM_USRP is appropriate
- Enable DEBUG=3 to see packet reception

**Distorted Audio:**
- Check PREAMP/NET_PREAMP (reduce if too high)
- Adjust LOCAL_LIMITER_THRESH, NET_LIMITER_THRESH
- Review filter configurations (may be too aggressive)
- Check for sample rate mismatches

**Metadata Not Working:**
- Verify DMRID, RPTID, DEFAULT_TG are set correctly
- Check Analog_Bridge configuration (JSON mode)
- Ensure MMDVMHost is configured for USRP input
- Check digital mode is correctly selected

---

## 14. REFERENCES

### 14.1 Source Files

**UsrpLogic Implementation:**
- `src/svxlink/svxlink/contrib/UsrpLogic/UsrpLogic.cpp:1-1221`
- `src/svxlink/svxlink/contrib/UsrpLogic/UsrpLogic.h:1-279`
- `src/svxlink/svxlink/contrib/UsrpLogic/UsrpMsg.h:1-502`

**USRP Protocol:**
- `src/svxlink/svxlink/contrib/UsrpLogic/usrp_protocol.txt:1-310`
- `src/svxlink/svxlink/contrib/UsrpLogic/usrp_metadata_json.txt:1-15`

**Async Audio Library:**
- `src/async/audio/*.h` (60+ files)
- `src/async/core/*.h`

**Logic Core:**
- `src/svxlink/svxlink/Logic.h`
- `src/svxlink/svxlink/LogicBase.h`

### 14.2 External Resources

**USRP Protocol Sources:**
- AllStar Asterisk: https://github.com/AllStarLink/ASL-Asterisk/blob/develop/asterisk/channels/chan_usrp.h
- MMDVM_Bridge: https://github.com/DVSwitch/MMDVM_Bridge/blob/master/dvswitch.sh
- USRP_Client: https://github.com/DVSwitch/USRP_Client/blob/master/pyUC.py

**Related Projects:**
- MMDVMHost: Multi-mode digital voice modem host
- Analog_Bridge: Bridge between analog and digital voice
- DV3000: AMBE hardware codec
- md380-emu: Software AMBE emulator

---

**Document Version:** 1.0
**Compiled by:** Claude Code AI Agent
**Analysis Agents Used:** 4 specialized exploration agents for comprehensive codebase analysis
