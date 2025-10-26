# PROCEDURĂ DE CALIBRARE OPTIMĂ - VAD ANTI-KERCHUNK

## Obiectiv

Calibrare precisă a sistemului Voice Activity Detection (VAD) pentru a atinge **90%+ acuratețe** în detectarea vocii reale vs kerchunk/zgomot.

---

## ETAPA 1: PREGĂTIRE SISTEM

### 1.1 Instalare Tool-uri de Monitoring

```bash
# 1. Activează debug logging în SVXLink
sudo nano /etc/svxlink/svxlink.conf

# Adaugă în fiecare secțiune:
[Rx1]
DEBUG=3  # DEBUG level pentru logging detaliat

[UsrpLogic]
DEBUG=3

# 2. Instalează tool-uri necesare
sudo apt-get install -y sox alsa-utils tcpdump netcat-openbsd

# 3. Creează director pentru log-uri calibrare
mkdir -p ~/svxlink-calibration/logs
cd ~/svxlink-calibration
```

### 1.2 Script de Monitoring Real-Time

Creează `monitor.sh`:

```bash
#!/bin/bash
# monitor.sh - Real-time monitoring pentru calibrare VAD

LOG_FILE="/var/log/svxlink.log"
OUTPUT_DIR="$HOME/svxlink-calibration/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_LOG="$OUTPUT_DIR/calibration_${TIMESTAMP}.log"

echo "=== SVXLink VAD Calibration Monitor ===" | tee -a $SESSION_LOG
echo "Session started: $(date)" | tee -a $SESSION_LOG
echo "" | tee -a $SESSION_LOG

# Terminal split în 4 panel-uri
tmux new-session -d -s svxlink_monitor

# Panel 1: SVXLink log (squelch events)
tmux send-keys -t svxlink_monitor "tail -f $LOG_FILE | grep --line-buffered -E 'Squelch|VOX|siglev|duration' | tee -a $SESSION_LOG" C-m
tmux split-window -v -t svxlink_monitor

# Panel 2: Audio level monitoring
tmux send-keys -t svxlink_monitor "watch -n 0.5 'echo \"=== Audio RX Level ===\"
amixer get PCM 2>/dev/null || echo \"No audio device\"
echo \"\"
echo \"=== UDP Traffic ===\"
netstat -s | grep \"packets received\" | tail -5'" C-m
tmux split-window -h -t svxlink_monitor

# Panel 3: USRP packet monitoring
tmux send-keys -t svxlink_monitor "sudo tcpdump -i lo -n -X port 41233 or port 41234 | grep --line-buffered USRP" C-m
tmux select-pane -t 0
tmux split-window -h -t svxlink_monitor

# Panel 4: Statistics calculator
tmux send-keys -t svxlink_monitor "cat > /tmp/vad_stats.sh << 'EOF'
#!/bin/bash
LOG=\"$SESSION_LOG\"
while true; do
  clear
  echo \"=== VAD STATISTICS ===\"
  echo \"\"
  TOTAL=\$(grep -c \"Squelch closed\" \$LOG 2>/dev/null || echo 0)
  KERCHUNK=\$(grep -c \"kerchunk\" \$LOG 2>/dev/null || echo 0)
  VALID=\$((TOTAL - KERCHUNK))
  if [ \$TOTAL -gt 0 ]; then
    VALID_PCT=\$(echo \"scale=1; \$VALID * 100 / \$TOTAL\" | bc)
    KERCHUNK_PCT=\$(echo \"scale=1; \$KERCHUNK * 100 / \$TOTAL\" | bc)
  else
    VALID_PCT=0
    KERCHUNK_PCT=0
  fi

  echo \"Total transmissions: \$TOTAL\"
  echo \"Valid voice: \$VALID (\${VALID_PCT}%)\"
  echo \"Kerchunk blocked: \$KERCHUNK (\${KERCHUNK_PCT}%)\"
  echo \"\"
  echo \"Target: >90% valid detection\"
  echo \"\"
  echo \"=== RECENT EVENTS ===\"
  tail -10 \$LOG | grep -E \"Squelch|duration\"
  sleep 2
done
EOF
chmod +x /tmp/vad_stats.sh
/tmp/vad_stats.sh" C-m

# Attach to session
tmux attach-session -t svxlink_monitor

echo ""
echo "Monitoring session created: svxlink_monitor"
echo "Log file: $SESSION_LOG"
echo ""
echo "To detach: Ctrl+B, then D"
echo "To reattach: tmux attach-session -t svxlink_monitor"
```

Rulează:
```bash
chmod +x monitor.sh
./monitor.sh
```

---

## ETAPA 2: CALIBRARE VOX_THRESH (Voice Detection)

### 2.1 Configurare Inițială Conservativă

```ini
# /etc/svxlink/svxlink.conf
[Rx1]
SQUELCH=VOX                   # Doar VOX pentru calibrare inițială
VOX_FILTER_DEPTH=300          # 300ms rolling window
VOX_THRESH=5000               # ⭐ START CONSERVATIV (prea mare intentionat)

# Disable alte filtre pentru calibrare pură
SQL_HANGTIME=0                # Temporarily disable
SQL_DELAY=0
SQL_START_DELAY=0

DEBUG=3                       # Maximum logging
```

Restart SVXLink:
```bash
sudo systemctl restart svxlink
```

### 2.2 Test 1: Detectare Nivel Zgomot de Fond

**Procedură:**

1. **NU transmite** nimic pe frecvența RX
2. Lasă sistemul în repaus 30 secunde
3. Monitorizează log-ul:

```bash
tail -f /var/log/svxlink.log | grep -i "rms\|vox\|level"
```

**Expected output:**
```
RMS level: 450  (zgomot de fond - statii in repaus)
RMS level: 520
RMS level: 380
...
VOX: signal NOT detected (rms=450 < thresh=5000)
```

**Înregistrează:**
```
Zgomot de fond maxim observat: _______ RMS
```

### 2.3 Test 2: Detectare Carrier Fără Modulație (Kerchunk Pur)

**Procedură:**

1. Transmite **carrier fără modulație** pe frecvența RX
2. Durata: 100ms (quick key-up)
3. **NU vorbi, NU fluiera** - doar PTT ON/OFF rapid

**Expected output:**
```
RMS level: 480  (carrier unmodulated - similar cu zgomot)
RMS level: 510
VOX: signal NOT detected (rms=500 < thresh=5000)
```

**Înregistrează:**
```
Carrier fără modulație: _______ RMS
```

**✅ SUCCES dacă:** VOX NU detectează semnalul (rms < threshold)

### 2.4 Test 3: Detectare Modulație Minimă (Șuierat/Test Tone)

**Procedură:**

1. Transmite cu **modulație minimă**:
   - Șuierat ușor SSSS sau FFFF
   - SAU test tone (whistle)
   - Durata: 200ms

**Expected output:**
```
RMS level: 1200  (modulație slabă)
RMS level: 1350
VOX: signal NOT detected (rms=1300 < thresh=5000)
```

**Înregistrează:**
```
Modulație minimă (test tone): _______ RMS
```

### 2.5 Test 4: Detectare Voce Slabă (Distant Station)

**Procedură:**

1. Transmite **voce normală** la nivel slab:
   - Distanță mare SAU power redus
   - Vorbește clar: "Test 1, 2, 3, repetor activ"
   - Durata: 2 secunde

**Expected output:**
```
RMS level: 2800  (voce slabă)
RMS level: 3200
RMS level: 2950
VOX: signal NOT detected (rms=3000 < thresh=5000)  # FAIL - threshold prea mare!
```

**Înregistrează:**
```
Voce slabă (distant): _______ RMS
```

**⚠️ AICI VOX ar trebui să DETECTEZE** - dacă nu, threshold e prea mare.

### 2.6 Test 5: Detectare Voce Normală (Local Station)

**Procedură:**

1. Transmite **voce normală** la nivel normal:
   - Distanță normală, power normal
   - Vorbește clar: "Bună ziua, test repetor, YourCall"
   - Durata: 3 secunde

**Expected output:**
```
RMS level: 5200  (voce normală)
RMS level: 6800
RMS level: 4500
VOX: signal DETECTED (rms=5500 > thresh=5000)  # SUCCES
Squelch opened on Rx1
```

**Înregistrează:**
```
Voce normală (local): _______ RMS
```

### 2.7 Test 6: Detectare Voce Puternică (Close Station)

**Procedură:**

1. Transmite **voce tare**:
   - Vorbește tare/strigă
   - Durata: 2 secunde

**Expected output:**
```
RMS level: 8500  (voce tare)
RMS level: 9200
VOX: signal DETECTED (rms=8800 > thresh=5000)  # SUCCES
```

**Înregistrează:**
```
Voce puternică (close): _______ RMS
```

### 2.8 Calculare VOX_THRESH Optim

**Formula:**

```
VOX_THRESH = MAX(zgomot_max, modulatie_minima, test_tone) * 1.5

SAU

VOX_THRESH = voce_slaba_min * 0.75
```

**Exemplu calculat:**

| Parametru | Valoare RMS |
|-----------|-------------|
| Zgomot de fond | 520 |
| Carrier fără modulație | 510 |
| Modulație minimă (test) | 1350 |
| Voce slabă | 3000 |
| Voce normală | 5500 |
| Voce puternică | 8800 |

**Calcul:**

```
Opțiune 1: MAX(520, 510, 1350) * 1.5 = 1350 * 1.5 = 2025  (PREA SLAB - va detecta teste)

Opțiune 2: 3000 * 0.75 = 2250  (BINE - va detecta voce slabă, va bloca teste)

⭐ RECOMMENDED: VOX_THRESH = 2500
   - Margin de siguranță peste modulație minimă
   - Sub voce slabă (va detecta)
```

**Aplică în configurare:**

```ini
[Rx1]
VOX_THRESH=2500  # ⭐ CALIBRAT
```

Restart:
```bash
sudo systemctl restart svxlink
```

### 2.9 Validare VOX_THRESH

**Re-rulează testele 2-6 și verifică:**

| Test | Expected Result |
|------|-----------------|
| Carrier fără modulație | ❌ NOT detected (rms < 2500) |
| Modulație minimă | ❌ NOT detected (rms < 2500) |
| Voce slabă | ✅ DETECTED (rms > 2500) |
| Voce normală | ✅ DETECTED (rms > 2500) |
| Voce puternică | ✅ DETECTED (rms > 2500) |

**✅ SUCCES:** Toate testele trec conform așteptărilor.

---

## ETAPA 3: CALIBRARE SQL_HANGTIME (Anti-Kerchunk Primary)

### 3.1 Activare SQL_HANGTIME

```ini
[Rx1]
VOX_THRESH=2500              # Din etapa 2
VOX_FILTER_DEPTH=300
SQL_HANGTIME=0               # ⭐ START FĂRĂ HANGTIME (calibrare)
SQL_DELAY=0
SQL_START_DELAY=0
DEBUG=3
```

Restart:
```bash
sudo systemctl restart svxlink
```

### 3.2 Test 1: Măsurare Durata Kerchunk Tipic

**Procedură:**

1. Quick key-up (PTT rapid ON/OFF)
2. **NU vorbi** - doar carrier
3. Cât mai rapid posibil (reflex natural)

**Expected output:**
```
Squelch opened on Rx1
Squelch closed on Rx1 (duration=85ms)  # ⭐ ÎNREGISTREAZĂ DURATA
```

**Repetă testul de 10 ori și înregistrează:**

```
Kerchunk #1: 85ms
Kerchunk #2: 92ms
Kerchunk #3: 78ms
Kerchunk #4: 110ms
Kerchunk #5: 95ms
Kerchunk #6: 88ms
Kerchunk #7: 102ms
Kerchunk #8: 81ms
Kerchunk #9: 94ms
Kerchunk #10: 89ms

Media: _______ ms
Maxim: _______ ms
```

**Exemplu calculat:**
- Media: 91ms
- Maxim: 110ms

### 3.3 Test 2: Măsurare Durata Transmisie Scurtă cu Modulație

**Procedură:**

1. PTT ON
2. Șuierat scurt "SSSS" (1 silab)
3. PTT OFF
4. Durata țintă: 200-300ms

**Expected output:**
```
Squelch opened on Rx1
Squelch closed on Rx1 (duration=245ms)  # ⭐ ÎNREGISTREAZĂ
```

**Repetă de 5 ori:**
```
Test scurt #1: 245ms
Test scurt #2: 280ms
Test scurt #3: 210ms
Test scurt #4: 265ms
Test scurt #5: 230ms

Media: _______ ms
```

### 3.4 Test 3: Măsurare Durata Voce Minimă Reală

**Procedură:**

1. PTT ON
2. Spune UN singur cuvânt: "Test"
3. PTT OFF

**Expected output:**
```
Squelch closed on Rx1 (duration=480ms)  # ⭐ VOCE MINIMĂ
```

**Repetă cu cuvinte scurte:**
```
"Test": 480ms
"Ok": 420ms
"Roger": 510ms
"YourCall": 650ms

Minim: _______ ms
```

### 3.5 Calculare SQL_HANGTIME Optim

**Formula:**

```
SQL_HANGTIME = MAX(kerchunk_max, test_scurt_max) + SAFETY_MARGIN

SAFETY_MARGIN = 100-200ms
```

**Exemplu calculat:**

```
Kerchunk maxim: 110ms
Test scurt maxim: 280ms
Voce minimă: 420ms

Opțiune 1: 280 + 100 = 380ms  (BINE - blochează teste scurte)
Opțiune 2: 280 + 150 = 430ms  (MAI SIGUR - deasupra vocii minime)

⭐ RECOMMENDED: SQL_HANGTIME = 400ms
   - Blochează kerchunk (< 110ms → 400ms delay → total < 510ms)
   - Blochează teste scurte (< 280ms → 400ms delay → total < 680ms)
   - Permite voce minimă (> 420ms → 400ms delay → total > 820ms)
```

**Logica SQL_HANGTIME:**

```
Durata efectivă transmisie = Durata_reala + SQL_HANGTIME

Exemplu:
- Kerchunk 100ms → 100 + 400 = 500ms (total duration logged)
- Test scurt 250ms → 250 + 400 = 650ms (total)
- Voce minimă 500ms → 500 + 400 = 900ms (total)
```

**Aplică:**

```ini
[Rx1]
SQL_HANGTIME=400  # ⭐ CALIBRAT
```

Restart:
```bash
sudo systemctl restart svxlink
```

### 3.6 Validare SQL_HANGTIME

**Re-rulează testele și verifică durata TOTALĂ:**

```bash
tail -f /var/log/svxlink.log | grep "duration"
```

| Test | Durata Reală | + SQL_HANGTIME | Total Duration | Result |
|------|--------------|----------------|----------------|--------|
| Kerchunk | 100ms | +400ms | 500ms | ❌ BLOCAT (< MIN_DURATION) |
| Test scurt | 250ms | +400ms | 650ms | ❌ BLOCAT |
| Voce minimă | 500ms | +400ms | 900ms | ✅ VALID |

---

## ETAPA 4: CALIBRARE DUAL SQUELCH (VOX + SIGLEV)

### 4.1 Activare SIGLEV Detector

```ini
[Rx1]
# Configurare din etapele anterioare
VOX_THRESH=2500
SQL_HANGTIME=400
VOX_FILTER_DEPTH=300

# ⭐ ADAUGĂ SIGLEV
SQL_DET=NOISE
SIGLEV_DET_INTEGRATION_TIME=300
SIGLEV_DET_BOGUS_THRESH=120

# ⭐ DUAL SQUELCH
SQUELCH=COMBINE
SQL_COMBINE=VOX AND SIGLEV    # Ambele trebuie TRUE

# SIGLEV thresholds - START conservativ
SQL_SIGLEV_OPEN_THRESH=30     # Prea mare (calibrare)
SQL_SIGLEV_CLOSE_THRESH=20    # Hysteresis

DEBUG=3
```

Restart:
```bash
sudo systemctl restart svxlink
```

### 4.2 Test 1: Măsurare SIGLEV Zgomot de Fond

**Procedură:**

1. **NU transmite** nimic
2. Lasă sistemul în repaus
3. Monitorizează:

```bash
tail -f /var/log/svxlink.log | grep -i "siglev"
```

**Expected output:**
```
Siglev: 0  (fără RF)
Siglev: 1
Siglev: 0
```

**Înregistrează:**
```
Siglev zgomot de fond: _______ (ar trebui 0-2)
```

### 4.3 Test 2: Măsurare SIGLEV Semnal Slab

**Procedură:**

1. Transmite de la **distanță mare** SAU **power redus**
2. Vorbește normal
3. Monitorizează siglev

**Expected output:**
```
Siglev: 8  (semnal slab)
Siglev: 12
Siglev: 9
VOX: signal DETECTED (rms=3200)
SIGLEV: signal NOT detected (siglev=10 < thresh=30)  # FAIL - threshold prea mare
Squelch: NOT opened (VOX=YES, SIGLEV=NO)
```

**Înregistrează:**
```
Siglev semnal slab: _______ (minim: ___, maxim: ___)
```

### 4.4 Test 3: Măsurare SIGLEV Semnal Normal

**Procedură:**

1. Transmite de la **distanță normală**
2. Vorbește normal

**Expected output:**
```
Siglev: 35  (semnal normal)
Siglev: 42
VOX: signal DETECTED (rms=5500)
SIGLEV: signal DETECTED (siglev=38 > thresh=30)
Squelch: OPENED (VOX=YES, SIGLEV=YES)  # SUCCES
```

**Înregistrează:**
```
Siglev semnal normal: _______ (minim: ___, maxim: ___)
```

### 4.5 Test 4: Măsurare SIGLEV Semnal Puternic

**Procedură:**

1. Transmite de la **distanță apropiată** SAU **power maxim**
2. Vorbește normal

**Expected output:**
```
Siglev: 75  (semnal puternic)
Siglev: 82
```

**Înregistrează:**
```
Siglev semnal puternic: _______ (minim: ___, maxim: ___)
```

### 4.6 Calculare SQL_SIGLEV_OPEN_THRESH Optim

**Formula:**

```
SQL_SIGLEV_OPEN_THRESH = siglev_slab_min * 0.8

SAU

SQL_SIGLEV_OPEN_THRESH = 15-20 (recommended default pentru FM repeater)
```

**Exemplu calculat:**

| Nivel Semnal | Siglev Min | Siglev Max |
|--------------|------------|------------|
| Zgomot fond | 0 | 2 |
| Semnal slab | 8 | 15 |
| Semnal normal | 30 | 50 |
| Semnal puternic | 70 | 90 |

**Calcul:**

```
Opțiune 1: 8 * 0.8 = 6.4 → 7  (PREA SLAB - poate detecta interferențe)
Opțiune 2: 15 * 0.8 = 12 → 12  (BINE - detectează semnal slab)

⭐ RECOMMENDED: SQL_SIGLEV_OPEN_THRESH = 15
   - Va detecta semnale slabe (siglev >= 15)
   - Va bloca zgomot de fond (siglev < 15)

SQL_SIGLEV_CLOSE_THRESH = 10
   - Hysteresis de 5 puncte (previne pickling)
```

**Aplică:**

```ini
[Rx1]
SQL_SIGLEV_OPEN_THRESH=15  # ⭐ CALIBRAT
SQL_SIGLEV_CLOSE_THRESH=10
```

Restart:
```bash
sudo systemctl restart svxlink
```

### 4.7 Validare Dual Squelch

**Test matrix:**

| Test | VOX | SIGLEV | Expected Squelch |
|------|-----|--------|------------------|
| Zgomot local (fără RF) | YES | NO | ❌ CLOSED (blocked) |
| Kerchunk (RF fără voce) | NO | YES | ❌ CLOSED (blocked) |
| Voce slabă (RF + voce) | YES | YES | ✅ OPENED |
| Voce normală | YES | YES | ✅ OPENED |

**Rulează toate testele și verifică rezultatele.**

---

## ETAPA 5: CALIBRARE SQL_EXTENDED_HANGTIME (Semnal Slab)

### 5.1 Test Semnal cu Dropouts

**Procedură:**

1. Transmite de la **distanță foarte mare** (siglev fluctuant)
2. Vorbește **continuu** 10 secunde
3. Monitorizează dacă squelch se deschide/închide (pickling)

**Expected output (FĂRĂ extended hangtime):**
```
Siglev: 12
Squelch opened
Siglev: 8  (sub threshold 10)
Squelch closed (duration=200ms)  # PICKLING - BAD
Siglev: 14
Squelch opened
Siglev: 9
Squelch closed (duration=180ms)  # PICKLING - BAD
```

**Problema:** Audio choppy ("ppp-ppp-ppp")

### 5.2 Activare SQL_EXTENDED_HANGTIME

```ini
[Rx1]
SQL_HANGTIME=400
SQL_EXTENDED_HANGTIME=1500         # ⭐ 1.5 sec pentru semnal slab
SQL_EXTENDED_HANGTIME_THRESH=18    # Activează când siglev < 18
```

Restart:
```bash
sudo systemctl restart svxlink
```

### 5.3 Re-test cu Extended Hangtime

**Expected output (CU extended hangtime):**
```
Siglev: 12 (< 18 → extended hangtime ENABLED)
Squelch opened
Siglev: 8  (dropout)
Squelch: hangtime active (1500ms)  # NU se închide imediat
Siglev: 14 (recovered)
Squelch: still open
...
(voce continuă smooth, fără pickling)
```

**✅ SUCCES:** Audio smooth, fără deschideri/închideri rapide.

### 5.4 Tuning SQL_EXTENDED_HANGTIME

**Ajustează în funcție de rezultate:**

| Simptom | Acțiune |
|---------|---------|
| Audio încă choppy la semnal slab | SQL_EXTENDED_HANGTIME += 500 |
| Kerchunk-uri lungi la semnal slab | SQL_EXTENDED_HANGTIME_THRESH -= 3 |
| Transmisii foarte lungi rămân deschise | SQL_EXTENDED_HANGTIME -= 300 |

**Valori recommended:**

```ini
SQL_EXTENDED_HANGTIME=1200         # 1.2 sec (start)
SQL_EXTENDED_HANGTIME_THRESH=15    # Siglev < 15 = semnal slab
```

---

## ETAPA 6: CALIBRARE SQL_START_DELAY și SQL_DELAY

### 6.1 Test TX/RX Commutation (Duplex Repeater)

**Doar dacă repetor e DUPLEX (RX și TX simultane):**

```ini
[Rx1]
SQL_START_DELAY=0  # START fără delay (test)
SQL_DELAY=0
```

Restart:
```bash
sudo systemctl restart svxlink
```

**Procedură:**

1. Transmite voce normală
2. Monitorizează dacă squelch se deschide IMEDIAT după TX OFF
3. Caută "spurious squelch open" în log

**Dacă vezi:**
```
TX OFF
Squelch opened on Rx1 (siglev=5)  # SPURIOUS - transient de la commutare
Squelch closed (duration=20ms)
```

**⚠️ Problema detectată:** TX OFF transients.

### 6.2 Calibrare SQL_START_DELAY

**Aplică delay după TX OFF:**

```ini
[Rx1]
SQL_START_DELAY=100  # 100ms deaf după TX OFF
```

**Re-test și verifică:**
```
TX OFF
(100ms deaf period - squelch disabled)
Squelch: ready after start delay
```

**✅ SUCCES:** Nu mai există spurious opens.

### 6.3 Calibrare SQL_DELAY (Voter/Multiple RX)

**Doar dacă folosești VOTER sau multiple receivers:**

```ini
[Rx1]
SQL_DELAY=50  # 50ms settling time pentru voter
```

**Altfel:**
```ini
SQL_DELAY=0  # NU e necesar pentru single RX
```

---

## ETAPA 7: IMPLEMENTARE MIN_TRANSMISSION_DURATION

### 7.1 Adaugă Parametru în svxlink.conf

```ini
[UsrpLogic]
# ... alte setări ...

# ⭐ MINIMUM DURATION pentru reflector
MIN_TRANSMISSION_DURATION=500  # 500ms (adjust după calibrare SQL_HANGTIME)
```

### 7.2 Cod Custom în UsrpLogic.cpp

**Modifică:** `src/svxlink/svxlink/contrib/UsrpLogic/UsrpLogic.cpp`

```cpp
// La începutul clasei, adaugă membri:
class UsrpLogic : public LogicBase {
private:
  std::chrono::steady_clock::time_point m_transmission_start;
  std::chrono::milliseconds m_min_transmission_duration{500};
  bool m_transmission_active = false;

  // ... restul membrilor ...
};

// În UsrpLogic::initialize(), citește parametrul:
bool UsrpLogic::initialize(Async::Config &cfg, const std::string &name) {
  // ... alte inițializări ...

  int min_dur = 500;
  if (cfg.getValue(name, "MIN_TRANSMISSION_DURATION", min_dur)) {
    m_min_transmission_duration = std::chrono::milliseconds(min_dur);
    std::cout << name << ": MIN_TRANSMISSION_DURATION="
              << min_dur << "ms" << std::endl;
  }

  return true;
}

// În event handler pentru stream state:
void UsrpLogic::onLogicConInStreamStateChanged(bool is_active, bool is_idle) {
  auto now = std::chrono::steady_clock::now();

  if (is_active && !m_transmission_active) {
    // Transmission START
    m_transmission_start = now;
    m_transmission_active = true;
    std::cout << name() << ": Transmission started" << std::endl;
  }

  if (is_idle && m_transmission_active) {
    // Transmission END
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
      now - m_transmission_start
    );

    std::cout << name() << ": Transmission ended, duration="
              << duration.count() << "ms" << std::endl;

    // ⭐ CHECK MINIMUM DURATION
    if (duration < m_min_transmission_duration) {
      std::cout << name() << ": *** KERCHUNK DETECTED ("
                << duration.count() << "ms < "
                << m_min_transmission_duration.count()
                << "ms) - BLOCKED ***" << std::endl;

      // NU trimite către reflector
      m_transmission_active = false;

      // Logare statistici (optional)
      // kerchunk_count++;

      // NU apela sendStopMsg() sau alte acțiuni reflector
      checkIdle();
      return;
    }

    // Transmisie VALIDĂ
    std::cout << name() << ": Valid transmission ("
              << duration.count() << "ms) - forwarding to reflector"
              << std::endl;

    // Continuă normal (trimite către reflector)
    sendStopMsg();
    m_transmission_active = false;
  }

  checkIdle();
}
```

### 7.3 Rebuild SVXLink

```bash
cd /private/tmp/svxlink/src
mkdir -p build
cd build

# Configure
cmake -DCMAKE_INSTALL_PREFIX=/usr -DSYSCONF_INSTALL_DIR=/etc \
      -DLOCAL_STATE_DIR=/var -DUSE_QT=OFF ..

# Build (doar UsrpLogic pentru viteză)
make -j$(nproc)

# Install
sudo make install

# Restart
sudo systemctl restart svxlink
```

### 7.4 Test MIN_TRANSMISSION_DURATION

**Test 1: Kerchunk (ar trebui blocat):**

```bash
# Transmite quick key-up
# Observă log:
tail -f /var/log/svxlink.log
```

**Expected:**
```
Transmission started
Squelch opened
Squelch closed (duration=500ms)  # 100ms real + 400ms hangtime
Transmission ended, duration=500ms
*** KERCHUNK DETECTED (500ms < 500ms) - BLOCKED ***
```

**⚠️ ATENȚIE:** Dacă duration = exact 500ms, ajustează threshold:

```ini
MIN_TRANSMISSION_DURATION=550  # Adaugă margin
```

**Test 2: Voce reală (ar trebui transmisă):**

```bash
# Vorbește: "Test, test, YourCall"
```

**Expected:**
```
Transmission started
Squelch opened
(audio flow...)
Squelch closed (duration=2300ms)  # 1900ms real + 400ms hangtime
Transmission ended, duration=2300ms
Valid transmission (2300ms) - forwarding to reflector
```

---

## ETAPA 8: VALIDARE FINALĂ ȘI MĂSURARE ACURATEȚE

### 8.1 Test Suite Complet

Creează `test_suite.sh`:

```bash
#!/bin/bash
# test_suite.sh - Comprehensive VAD testing

LOG_FILE="$HOME/svxlink-calibration/logs/test_suite_$(date +%Y%m%d_%H%M%S).log"

echo "=== SVXLink VAD Test Suite ===" | tee $LOG_FILE
echo "Started: $(date)" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# Counters
TOTAL=0
PASSED=0
FAILED=0

# Helper function
run_test() {
  local test_name="$1"
  local expected_result="$2"  # "BLOCKED" or "ALLOWED"

  TOTAL=$((TOTAL + 1))

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a $LOG_FILE
  echo "TEST #$TOTAL: $test_name" | tee -a $LOG_FILE
  echo "Expected: $expected_result" | tee -a $LOG_FILE
  echo "" | tee -a $LOG_FILE
  echo "Press ENTER when ready to transmit..." | tee -a $LOG_FILE
  read

  echo "Waiting for transmission..." | tee -a $LOG_FILE
  sleep 5

  # Check log pentru rezultat
  RESULT=$(tail -20 /var/log/svxlink.log | grep -E "BLOCKED|forwarding to reflector" | tail -1)

  echo "Result: $RESULT" | tee -a $LOG_FILE

  if echo "$RESULT" | grep -q "BLOCKED" && [ "$expected_result" == "BLOCKED" ]; then
    echo "✅ PASSED" | tee -a $LOG_FILE
    PASSED=$((PASSED + 1))
  elif echo "$RESULT" | grep -q "forwarding" && [ "$expected_result" == "ALLOWED" ]; then
    echo "✅ PASSED" | tee -a $LOG_FILE
    PASSED=$((PASSED + 1))
  else
    echo "❌ FAILED" | tee -a $LOG_FILE
    FAILED=$((FAILED + 1))
  fi

  echo "" | tee -a $LOG_FILE
}

# RUN TESTS
run_test "Kerchunk pur (quick key-up, fără modulație)" "BLOCKED"
run_test "Carrier fără voce (100ms)" "BLOCKED"
run_test "Test tone scurt (200ms)" "BLOCKED"
run_test "Șuierat scurt (300ms)" "BLOCKED"
run_test "Un singur cuvânt scurt: 'Ok' (400ms)" "BLOCKED"
run_test "Voce minimă: 'Test' (500ms)" "ALLOWED"
run_test "Voce normală: 'Bună ziua' (1 sec)" "ALLOWED"
run_test "Voce normală: frază completă (2-3 sec)" "ALLOWED"
run_test "Zgomot local (fără RF)" "BLOCKED"
run_test "Semnal slab cu dropouts (voce 5 sec)" "ALLOWED"

# SUMMARY
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a $LOG_FILE
echo "=== TEST SUMMARY ===" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE
echo "Total tests: $TOTAL" | tee -a $LOG_FILE
echo "Passed: $PASSED" | tee -a $LOG_FILE
echo "Failed: $FAILED" | tee -a $LOG_FILE

if [ $TOTAL -gt 0 ]; then
  ACCURACY=$(echo "scale=1; $PASSED * 100 / $TOTAL" | bc)
  echo "Accuracy: ${ACCURACY}%" | tee -a $LOG_FILE

  if (( $(echo "$ACCURACY >= 90" | bc -l) )); then
    echo "" | tee -a $LOG_FILE
    echo "🎯 SUCCESS: Accuracy >= 90% - TARGET ACHIEVED!" | tee -a $LOG_FILE
  else
    echo "" | tee -a $LOG_FILE
    echo "⚠️  WARNING: Accuracy < 90% - additional tuning required" | tee -a $LOG_FILE
  fi
fi

echo "" | tee -a $LOG_FILE
echo "Log saved to: $LOG_FILE" | tee -a $LOG_FILE
```

Rulează:
```bash
chmod +x test_suite.sh
./test_suite.sh
```

### 8.2 Interpretare Rezultate

**Target: >= 90% accuracy (9/10 teste corecte)**

**Dacă accuracy < 90%:**

| Problema | Acțiune |
|----------|---------|
| Kerchunk trece (FALSE POSITIVE) | VOX_THRESH += 500, SQL_HANGTIME += 100 |
| Teste scurte trec | SQL_HANGTIME += 100, MIN_DURATION += 100 |
| Voce reală blocată (FALSE NEGATIVE) | VOX_THRESH -= 500 |
| Zgomot local detectat | Activează SQL_COMBINE=VOX AND SIGLEV |

---

## ETAPA 9: CONFIGURARE FINALĂ OPTIMIZATĂ

### 9.1 Configurare Completă svxlink.conf

```ini
[GLOBAL]
MODULE_PATH=/usr/lib/svxlink
LOGICS=UsrpLogic
CFG_DIR=/etc/svxlink/svxlink.d
TIMESTAMP_FORMAT="%c"
CARD_SAMPLE_RATE=16000
CARD_CHANNELS=1

# ════════════════════════════════════════════════════════
# RX1: GM340 RX → MMDVM (CALIBRAT)
# ════════════════════════════════════════════════════════
[Rx1]
TYPE=Local
AUDIO_DEV=alsa:plughw:1
AUDIO_CHANNEL=0

# ⭐ VOICE ACTIVITY DETECTION (calibrat în ETAPA 2)
SQUELCH=COMBINE
SQL_COMBINE=VOX AND SIGLEV

# VOX Configuration
VOX_FILTER_DEPTH=300
VOX_THRESH=2500              # ⭐ CALIBRAT

# SIGLEV Configuration
SQL_DET=NOISE
SIGLEV_DET_INTEGRATION_TIME=400
SIGLEV_DET_BOGUS_THRESH=120
SQL_SIGLEV_OPEN_THRESH=15    # ⭐ CALIBRAT
SQL_SIGLEV_CLOSE_THRESH=10

# ⭐ ANTI-KERCHUNK TIMING (calibrat în ETAPA 3, 5, 6)
SQL_START_DELAY=100          # ⭐ CALIBRAT (sau 0 dacă simplex)
SQL_DELAY=0                  # ⭐ CALIBRAT (sau 50 dacă voter)
SQL_HANGTIME=400             # ⭐ CALIBRAT - PRIMARY ANTI-KERCHUNK
SQL_EXTENDED_HANGTIME=1200   # ⭐ CALIBRAT
SQL_EXTENDED_HANGTIME_THRESH=15
SQL_TIMEOUT=180

# Audio
AUDIO_GAIN=0

# Debug (reduce la 1 pentru production)
DEBUG=1

# ════════════════════════════════════════════════════════
# UsrpLogic: Bridge către reflector (calibrat în ETAPA 7)
# ════════════════════════════════════════════════════════
[UsrpLogic]
TYPE=Usrp
CALLSIGN=YourCall

# Network
USRP_HOST=127.0.0.1
USRP_TX_PORT=41234
USRP_RX_PORT=41233

# ⭐ MINIMUM DURATION (calibrat în ETAPA 7)
MIN_TRANSMISSION_DURATION=550  # ⭐ CALIBRAT (500 + margin)

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
DEBUG=1

# Parametri DMR (nu folosiți)
DMRID=0
RPTID=0
DEFAULT_TG=0
DEFAULT_CC=0
DEFAULT_TS=0
```

### 9.2 Backup Configurare

```bash
# Backup configurație calibrată
sudo cp /etc/svxlink/svxlink.conf \
        /etc/svxlink/svxlink.conf.calibrated_$(date +%Y%m%d)

# Salvează parametri calibrați
cat > ~/svxlink-calibration/calibration_params.txt << EOF
=== SVXLink VAD Calibration Parameters ===
Date: $(date)

[Rx1]
VOX_THRESH=$VOX_THRESH_VALUE
SQL_SIGLEV_OPEN_THRESH=$SIGLEV_OPEN_VALUE
SQL_SIGLEV_CLOSE_THRESH=$SIGLEV_CLOSE_VALUE
SQL_HANGTIME=$HANGTIME_VALUE
SQL_EXTENDED_HANGTIME=$EXTENDED_HANGTIME_VALUE
SQL_EXTENDED_HANGTIME_THRESH=$EXTENDED_THRESH_VALUE
SQL_START_DELAY=$START_DELAY_VALUE
SQL_DELAY=$DELAY_VALUE

[UsrpLogic]
MIN_TRANSMISSION_DURATION=$MIN_DURATION_VALUE

Test Suite Accuracy: XX.X%
EOF
```

---

## ETAPA 10: MONITORING CONTINUU ȘI FINE-TUNING

### 10.1 Script de Monitoring în Producție

Creează `production_monitor.sh`:

```bash
#!/bin/bash
# production_monitor.sh - Production monitoring cu statistici

LOG_DIR="$HOME/svxlink-monitoring"
mkdir -p $LOG_DIR

DATE=$(date +%Y%m%d)
LOG_FILE="$LOG_DIR/stats_${DATE}.log"

# Monitorizează statistici zilnice
while true; do
  TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)

  # Extrage statistici din log SVXLink
  TOTAL=$(grep -c "Transmission ended" /var/log/svxlink.log)
  BLOCKED=$(grep -c "KERCHUNK DETECTED" /var/log/svxlink.log)
  VALID=$(grep -c "forwarding to reflector" /var/log/svxlink.log)

  if [ $TOTAL -gt 0 ]; then
    VALID_PCT=$(echo "scale=2; $VALID * 100 / $TOTAL" | bc)
    BLOCKED_PCT=$(echo "scale=2; $BLOCKED * 100 / $TOTAL" | bc)
  else
    VALID_PCT=0
    BLOCKED_PCT=0
  fi

  # Log statistici
  echo "$TIMESTAMP | Total=$TOTAL | Valid=$VALID ($VALID_PCT%) | Blocked=$BLOCKED ($BLOCKED_PCT%)" >> $LOG_FILE

  # Display
  echo "[$TIMESTAMP] Valid: $VALID_PCT% | Blocked: $BLOCKED_PCT%"

  # Sleep 1 hour
  sleep 3600
done
```

Rulează în background:
```bash
chmod +x production_monitor.sh
nohup ./production_monitor.sh &
```

### 10.2 Alert System

Creează `alert_check.sh`:

```bash
#!/bin/bash
# alert_check.sh - Alert dacă accuracy scade sub 90%

THRESHOLD=90

TOTAL=$(grep -c "Transmission ended" /var/log/svxlink.log)
VALID=$(grep -c "forwarding to reflector" /var/log/svxlink.log)

if [ $TOTAL -gt 10 ]; then  # Minimum 10 samples
  VALID_PCT=$(echo "scale=1; $VALID * 100 / $TOTAL" | bc)

  if (( $(echo "$VALID_PCT < $THRESHOLD" | bc -l) )); then
    # Send alert (email, notification, etc.)
    echo "⚠️  ALERT: VAD accuracy dropped to ${VALID_PCT}% (< ${THRESHOLD}%)" | \
      mail -s "SVXLink VAD Alert" your_email@example.com
  fi
fi
```

Adaugă în crontab (check hourly):
```bash
crontab -e

# Adaugă linia:
0 * * * * /home/youruser/svxlink-calibration/alert_check.sh
```

---

## REZUMAT CALIBRARE

### Parametri Calibrați

| Parametru | Valoare Tipică | Ajustare |
|-----------|----------------|----------|
| VOX_THRESH | 2500-3500 | ±500 |
| SQL_SIGLEV_OPEN_THRESH | 15-20 | ±3 |
| SQL_SIGLEV_CLOSE_THRESH | 10-15 | ±3 |
| SQL_HANGTIME | 300-500 | ±100 |
| SQL_EXTENDED_HANGTIME | 1000-1500 | ±200 |
| SQL_EXTENDED_HANGTIME_THRESH | 15-20 | ±3 |
| SQL_START_DELAY | 0-150 | ±50 |
| SQL_DELAY | 0-50 | ±20 |
| MIN_TRANSMISSION_DURATION | 500-600 | ±50 |

### Pași pentru Re-calibrare

Dacă accuracy scade în timp:

1. **Rulează test_suite.sh** pentru a identifica testele failed
2. **Analizează pattern-ul erorilor:**
   - False positives (kerchunk trece) → crește VOX_THRESH, SQL_HANGTIME
   - False negatives (voce blocată) → reduce VOX_THRESH
3. **Ajustează UN parametru odată** cu increment mic (±100-500)
4. **Re-testează** după fiecare modificare
5. **Validează** cu test_suite.sh
6. **Monitorizează** 24h înainte să confirmi calibrarea

### Obiectiv Final

✅ **90%+ accuracy** în detectarea vocii reale
✅ **<5% false positives** (kerchunk trece)
✅ **<5% false negatives** (voce blocată)
✅ **Latență <150ms** end-to-end (RX → reflector)
✅ **Audio smooth** fără pickling la semnal slab

---

**CALIBRAREA E COMPLETĂ!** 🎯
