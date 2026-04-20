# Atriarch System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete reactive target training system: target firmware, transmitter firmware, and Flutter control app.

**Architecture:** Three independent subsystems connected by defined protocols. Target firmware (Arduino) handles LED/vibration state machine. Transmitter firmware (ATmega328P) parses BLE commands and orchestrates drills via NRF24. Flutter app provides configuration UI, drill timer, and post-drill results.

**Tech Stack:** Arduino/C++ (target + transmitter firmware), RF24/RF24Network libraries, FastLED, Flutter/Dart, flutter_blue_plus, Provider, Syncfusion Excel.

**Spec:** `docs/superpowers/specs/2026-03-31-atriarch-system-design.md`

---

## File Map

### Firmware — Target (`firmware/target/`)

| File | Responsibility |
|------|---------------|
| `firmware/target/target.ino` | Main sketch: setup, loop, state machine, NRF24 comms, LED control, vibration sensing |
| `firmware/target/config.h` | Pin definitions, RF24 settings, command/event constants, vibration threshold |

### Firmware — Transmitter (`firmware/transmitter/`)

| File | Responsibility |
|------|---------------|
| `firmware/transmitter/transmitter.ino` | Main sketch: setup, loop, serial parsing, NRF24 relay, group state machines |
| `firmware/transmitter/config.h` | Pin definitions, RF24 settings, command/event constants, address map |
| `firmware/transmitter/serial_parser.h` | BLE serial command buffer and parser |
| *(GroupState struct is inline in transmitter.ino)* | Per-group state machine struct and tick logic |

### Flutter App (`lib/`)

| File | Responsibility |
|------|---------------|
| `lib/main.dart` | App entry, MaterialApp, Provider setup, route to BLE check |
| `lib/services/ble_service.dart` | BLE scan, connect, disconnect, service discovery, write, notify |
| `lib/services/transmitter_protocol.dart` | Encode app commands, decode telemetry strings |
| `lib/models/target_unit.dart` | Target data: id, isOnline, groupId, isNoShoot |
| `lib/models/target_group.dart` | Group: id, name, list of target IDs |
| `lib/models/drill_config.dart` | Program type, timing, hits, groups, no-shoot list, iterations |
| `lib/models/drill_session.dart` | Runtime state: events list, start time, running flag |
| `lib/models/session_event.dart` | Event types: activation, hit, complete, no-shoot, late-hit |
| `lib/state/app_state.dart` | ChangeNotifier: BLE state, targets, drill config, session |
| `lib/screens/device_discovery_screen.dart` | BLE device scan + connect |
| `lib/screens/home_screen.dart` | Main menu: Program A, Program B, Target Setup |
| `lib/screens/target_discovery_screen.dart` | NRF24 scan, identify, group assignment |
| `lib/screens/program_a_setup_screen.dart` | Grouped mode configuration |
| `lib/screens/program_b_setup_screen.dart` | Individual mode configuration |
| `lib/screens/drill_running_screen.dart` | Timer + Stop (events accumulated silently) |
| `lib/screens/results_screen.dart` | Post-drill stats, per-target summary, export |
| `lib/widgets/inc_dec.dart` | Numeric +/- input (migrated from current app) |
| `lib/widgets/target_chip.dart` | Small target indicator for group assignment UI |

---

## Phase 1: Target Firmware

The simplest subsystem — no serial parsing, no orchestration. Just a state machine that responds to NRF24 commands. Can be tested with a second Arduino acting as a fake transmitter.

### Task 1.1: Project scaffold and config

**Files:**
- Create: `firmware/target/config.h`
- Create: `firmware/target/target.ino`

- [ ] **Step 1: Create config.h with all constants**

```cpp
// firmware/target/config.h
#ifndef CONFIG_H
#define CONFIG_H

// --- Pin Definitions ---
#define LED_STRIP_PIN   5
#define NUM_LEDS        6
#define RELAY_PIN       2
#define VIBRATION_PIN   A3
#define NRF_CE_PIN      10
#define NRF_CSN_PIN     9

// --- RF24 Settings ---
#define RF24_CHANNEL    90
// NODE_ADDRESS must be set per-target before flashing.
// Use octal: 01, 02, 03, 04, 05 (level 1)
//            011, 021, 031, 041, 051 (level 2, children of 01)
//            012, 022, 032, 042, 052 (level 2, children of 02)
//            etc.
#define NODE_ADDRESS    01  // <-- CHANGE THIS PER TARGET

// --- Command Constants (transmitter -> target) ---
#define CMD_ACTIVATE    1
#define CMD_DEACTIVATE  2
#define CMD_IDENTIFY    3
#define CMD_PING        4

// --- Event Constants (target -> transmitter) ---
#define EVT_PONG        10
#define EVT_HIT         11
#define EVT_COMPLETE    12
#define EVT_NOSHOOT_HIT 13
#define EVT_LATE_HIT    14

// --- Color Modes ---
#define COLOR_NORMAL    1
#define COLOR_NOSHOOT   2

// --- Target States ---
#define STATE_IDLE          0
#define STATE_ACTIVE_SHOOT  1
#define STATE_ACTIVE_NOSHOOT 2
#define STATE_COOLDOWN      3
#define STATE_IDENTIFYING   4

// --- Timing ---
#define COOLDOWN_MS         2000
#define IDENTIFY_FLASH_MS   300
#define IDENTIFY_FLASHES    3
#define VIB_DEBOUNCE_MS     100
#define LATE_HIT_FLASH_MS   200

// --- Vibration ---
#define VIB_THRESHOLD       20  // pulseIn microseconds; tune per hardware

// --- NRF24 Message Size ---
#define MSG_SIZE 3  // max ints in a command/event payload

#endif
```

- [ ] **Step 2: Create target.ino with includes, globals, and empty setup/loop**

```cpp
// firmware/target/target.ino
#include <SPI.h>
#include <RF24.h>
#include <RF24Network.h>
#include <FastLED.h>
#include "config.h"

RF24 radio(NRF_CE_PIN, NRF_CSN_PIN);
RF24Network network(radio);

CRGB leds[NUM_LEDS];

// State
int state = STATE_IDLE;
int requiredHits = 0;
int hitCount = 0;
unsigned long activationTime = 0;
unsigned long cooldownStart = 0;
unsigned long lastVibTime = 0;
unsigned long identifyStart = 0;
int identifyFlashCount = 0;
bool identifyLedOn = false;

void setup() {
  Serial.begin(9600);
  
  // NRF24
  SPI.begin();
  radio.begin();
  network.begin(RF24_CHANNEL, NODE_ADDRESS);
  radio.setDataRate(RF24_2MBPS);
  
  // LEDs
  FastLED.addLeds<WS2812, LED_STRIP_PIN, GRB>(leds, NUM_LEDS);
  fill_solid(leds, NUM_LEDS, CRGB::Black);
  FastLED.show();
  
  // Relay
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  
  // Vibration sensor
  pinMode(VIBRATION_PIN, INPUT);
  
  randomSeed(analogRead(0));
  
  Serial.print("Target node 0");
  Serial.print(NODE_ADDRESS, OCT);
  Serial.println(" ready.");
}

void loop() {
  network.update();
  handleIncoming();
  handleState();
}
```

- [ ] **Step 3: Verify it compiles**

Open Arduino IDE, set board to "Arduino Nano" (ATmega328P), verify/compile. Expected: compiles with warnings about unused functions only (handleIncoming/handleState not yet defined — will fail at link). This is expected; we'll add them next.

- [ ] **Step 4: Commit**

```bash
git add firmware/target/config.h firmware/target/target.ino
git commit -m "feat(target): scaffold target firmware with config and setup"
```

### Task 1.2: NRF24 message receiving and sending

**Files:**
- Modify: `firmware/target/target.ino`

- [ ] **Step 1: Add sendEvent() helper**

Add after the `loop()` function:

```cpp
void sendEvent(int eventType, int param1, int param2) {
  int payload[MSG_SIZE] = {eventType, param1, param2};
  RF24NetworkHeader header(00);  // send to master node
  network.write(header, &payload, sizeof(payload));
}
```

- [ ] **Step 2: Add handleIncoming() to process NRF24 commands**

```cpp
void handleIncoming() {
  while (network.available()) {
    RF24NetworkHeader header;
    int payload[MSG_SIZE] = {0, 0, 0};
    network.read(header, &payload, sizeof(payload));
    
    int cmd = payload[0];
    
    switch (cmd) {
      case CMD_PING:
        sendEvent(EVT_PONG, NODE_ADDRESS, 0);
        break;
        
      case CMD_IDENTIFY:
        state = STATE_IDENTIFYING;
        identifyStart = millis();
        identifyFlashCount = 0;
        identifyLedOn = false;
        break;
        
      case CMD_ACTIVATE:
        requiredHits = payload[1];
        hitCount = 0;
        activationTime = millis();
        if (payload[2] == COLOR_NOSHOOT) {
          state = STATE_ACTIVE_NOSHOOT;
        } else {
          state = STATE_ACTIVE_SHOOT;
        }
        setLedGreen();
        break;
        
      case CMD_DEACTIVATE:
        state = STATE_IDLE;
        setLedOff();
        break;
    }
  }
}
```

- [ ] **Step 3: Verify it compiles**

Expected: compile error for missing setLedGreen, setLedOff, handleState. Expected at this stage.

- [ ] **Step 4: Commit**

```bash
git add firmware/target/target.ino
git commit -m "feat(target): add NRF24 message receive and send helpers"
```

### Task 1.3: LED control helpers

**Files:**
- Modify: `firmware/target/target.ino`

- [ ] **Step 1: Add LED helper functions**

Add before `sendEvent()`:

```cpp
void setLedGreen() {
  fill_solid(leds, NUM_LEDS, CRGB::Green);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedRed() {
  fill_solid(leds, NUM_LEDS, CRGB::Red);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedYellow() {
  fill_solid(leds, NUM_LEDS, CRGB::Yellow);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedWhite() {
  fill_solid(leds, NUM_LEDS, CRGB::White);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedOff() {
  fill_solid(leds, NUM_LEDS, CRGB::Black);
  FastLED.show();
  digitalWrite(RELAY_PIN, LOW);
}
```

- [ ] **Step 2: Commit**

```bash
git add firmware/target/target.ino
git commit -m "feat(target): add LED control helpers for all states"
```

### Task 1.4: Vibration detection helper

**Files:**
- Modify: `firmware/target/target.ino`

- [ ] **Step 1: Add checkVibration() function**

Add after the LED helpers:

```cpp
bool checkVibration() {
  long measurement = pulseIn(VIBRATION_PIN, HIGH, 1000); // 1ms timeout
  if (measurement > VIB_THRESHOLD) {
    unsigned long now = millis();
    if (now - lastVibTime > VIB_DEBOUNCE_MS) {
      lastVibTime = now;
      return true;
    }
  }
  return false;
}
```

Note: `pulseIn` with a timeout of 1000us prevents blocking. The debounce prevents double-counting a single hit.

- [ ] **Step 2: Commit**

```bash
git add firmware/target/target.ino
git commit -m "feat(target): add vibration detection with debounce"
```

### Task 1.5: State machine — handleState()

**Files:**
- Modify: `firmware/target/target.ino`

- [ ] **Step 1: Add handleState() function**

```cpp
void handleState() {
  unsigned long now = millis();
  
  switch (state) {
    case STATE_IDLE:
      // Nothing to do — waiting for commands
      break;
      
    case STATE_ACTIVE_SHOOT:
      if (checkVibration()) {
        hitCount++;
        unsigned long elapsed = now - activationTime;
        if (hitCount >= requiredHits) {
          sendEvent(EVT_COMPLETE, hitCount, (int)(elapsed & 0x7FFF));
          setLedOff();
          cooldownStart = now;
          state = STATE_COOLDOWN;
        } else {
          sendEvent(EVT_HIT, hitCount, (int)(elapsed & 0x7FFF));
        }
      }
      break;
      
    case STATE_ACTIVE_NOSHOOT:
      if (checkVibration()) {
        unsigned long elapsed = now - activationTime;
        setLedRed();
        sendEvent(EVT_NOSHOOT_HIT, (int)(elapsed & 0x7FFF), 0);
        // Stay in ACTIVE_NOSHOOT — transmitter will CMD_DEACTIVATE when timer expires
      }
      break;
      
    case STATE_COOLDOWN:
      if (now - cooldownStart >= COOLDOWN_MS) {
        state = STATE_IDLE;
      } else if (checkVibration()) {
        unsigned long elapsed = now - activationTime;
        setLedYellow();
        sendEvent(EVT_LATE_HIT, (int)(elapsed & 0x7FFF), 0);
        // Brief flash then back to off
        delay(LATE_HIT_FLASH_MS);
        setLedOff();
      }
      break;
      
    case STATE_IDENTIFYING:
      handleIdentify(now);
      break;
  }
}

void handleIdentify(unsigned long now) {
  unsigned long elapsed = now - identifyStart;
  int flashPhase = elapsed / IDENTIFY_FLASH_MS;
  
  if (flashPhase >= IDENTIFY_FLASHES * 2) {
    // Done flashing
    setLedOff();
    state = STATE_IDLE;
    return;
  }
  
  bool shouldBeOn = (flashPhase % 2 == 0);
  if (shouldBeOn && !identifyLedOn) {
    setLedWhite();
    identifyLedOn = true;
  } else if (!shouldBeOn && identifyLedOn) {
    setLedOff();
    identifyLedOn = false;
  }
}
```

- [ ] **Step 2: Verify full sketch compiles**

Open Arduino IDE, verify/compile for Arduino Nano (ATmega328P). Expected: clean compile, no errors.

- [ ] **Step 3: Commit**

```bash
git add firmware/target/target.ino
git commit -m "feat(target): implement full state machine with all target behaviors"
```

### Task 1.6: Hardware test

- [ ] **Step 1: Flash to a target unit**

Set `NODE_ADDRESS` to `01` in `config.h`. Upload to an Arduino Nano.

- [ ] **Step 2: Verify serial output**

Open Serial Monitor at 9600 baud. Expected: `Target node 01 ready.`

- [ ] **Step 3: Test with a fake transmitter (optional)**

If a second Arduino with NRF24 is available, send a `{CMD_PING}` packet to node 01 and verify you receive `{EVT_PONG, 1, 0}` back. Otherwise, defer to integration testing with the real transmitter.

---

## Phase 2: Transmitter Firmware

The transmitter is the most complex firmware piece: serial parsing, address mapping, NRF24 relay, and per-group state machines — all non-blocking.

### Task 2.1: Project scaffold and config

**Files:**
- Create: `firmware/transmitter/config.h`
- Create: `firmware/transmitter/transmitter.ino`

- [ ] **Step 1: Create config.h**

```cpp
// firmware/transmitter/config.h
#ifndef CONFIG_H
#define CONFIG_H

// --- Pin Definitions ---
#define NRF_CE_PIN      10
#define NRF_CSN_PIN     9

// --- RF24 Settings ---
#define RF24_CHANNEL    90
#define MASTER_ADDRESS  00

// --- Command Constants (to targets) ---
#define CMD_ACTIVATE    1
#define CMD_DEACTIVATE  2
#define CMD_IDENTIFY    3
#define CMD_PING        4

// --- Event Constants (from targets) ---
#define EVT_PONG        10
#define EVT_HIT         11
#define EVT_COMPLETE    12
#define EVT_NOSHOOT_HIT 13
#define EVT_LATE_HIT    14

// --- Color Modes ---
#define COLOR_NORMAL    1
#define COLOR_NOSHOOT   2

// --- Limits ---
#define MAX_TARGETS     30
#define MAX_GROUPS      5
#define MAX_TARGETS_PER_GROUP 10
#define SERIAL_BUF_SIZE 256

// --- NRF24 Message Size ---
#define MSG_SIZE 3

// --- Group States ---
#define GRP_IDLE            0
#define GRP_WAITING_START   1
#define GRP_SELECT_TARGET   2
#define GRP_WAITING_COMPLETE 3
#define GRP_WAITING_DELAY   4
#define GRP_DONE            5

#endif
```

- [ ] **Step 2: Create transmitter.ino scaffold**

```cpp
// firmware/transmitter/transmitter.ino
#include <SPI.h>
#include <RF24.h>
#include <RF24Network.h>
#include "config.h"

RF24 radio(NRF_CE_PIN, NRF_CSN_PIN);
RF24Network network(radio);

// --- Address Mapping: decimal ID (1-30) -> octal RF24Network address ---
const uint16_t addressMap[MAX_TARGETS + 1] = {
  0,                                      // index 0 unused
  01, 02, 03, 04, 05,                     // 1-5:   level 1
  011, 021, 031, 041, 051,                // 6-10:  children of 01
  012, 022, 032, 042, 052,                // 11-15: children of 02
  013, 023, 033, 043, 053,                // 16-20: children of 03
  014, 024, 034, 044, 054,                // 21-25: children of 04
  015, 025, 035, 045, 055                 // 26-30: children of 05
};

// --- Serial Buffer ---
char serialBuf[SERIAL_BUF_SIZE];
int serialPos = 0;

// --- Drill Config ---
float startMin, startMax, delayMin, delayMax;
int hitsMin, hitsMax;
int iterations;
bool drillRunning = false;

// --- Group State ---
struct GroupState {
  int state;
  int targets[MAX_TARGETS_PER_GROUP];
  int targetCount;
  bool noShoot[MAX_TARGETS_PER_GROUP]; // true if target is no-shoot
  int activeTargetIdx;                  // index into targets[]
  int activeTargetAddr;                 // decimal ID of active target
  int requiredHits;
  int iterationsLeft;
  unsigned long timerStart;
  unsigned long timerDuration;
};

GroupState groups[MAX_GROUPS];
int activeGroupCount = 0;

// --- No-shoot list ---
int noShootTargets[MAX_TARGETS];
int noShootCount = 0;

void setup() {
  Serial.begin(9600);
  
  SPI.begin();
  radio.begin();
  network.begin(RF24_CHANNEL, MASTER_ADDRESS);
  radio.setDataRate(RF24_2MBPS);
  
  randomSeed(analogRead(0));
  
  Serial.println("Transmitter ready.");
}

void loop() {
  network.update();
  readSerial();
  handleNrfEvents();
  if (drillRunning) {
    tickGroups();
  }
}
```

- [ ] **Step 3: Verify it compiles**

Expected: compile errors for missing readSerial, handleNrfEvents, tickGroups. Expected at this stage.

- [ ] **Step 4: Commit**

```bash
git add firmware/transmitter/config.h firmware/transmitter/transmitter.ino
git commit -m "feat(transmitter): scaffold transmitter firmware with config and address map"
```

### Task 2.2: Serial buffer and command parser

**Files:**
- Create: `firmware/transmitter/serial_parser.h`
- Modify: `firmware/transmitter/transmitter.ino`

- [ ] **Step 1: Create serial_parser.h**

```cpp
// firmware/transmitter/serial_parser.h
#ifndef SERIAL_PARSER_H
#define SERIAL_PARSER_H

#include <Arduino.h>

// Parse a comma-separated list of ints like "1,11,21" into an array.
// Returns number of values parsed.
int parseIntList(const char* str, int* out, int maxCount) {
  int count = 0;
  const char* p = str;
  while (*p && count < maxCount) {
    out[count] = atoi(p);
    count++;
    // Advance past this number
    while (*p && *p != ',') p++;
    if (*p == ',') p++;
  }
  return count;
}

// Parse a float from a string, advance pointer past the value.
float parseNextFloat(char** p) {
  float val = atof(*p);
  // Advance past this field to next '/'
  while (**p && **p != '/') (*p)++;
  if (**p == '/') (*p)++;
  return val;
}

// Parse an int from a string, advance pointer past the value.
int parseNextInt(char** p) {
  int val = atoi(*p);
  while (**p && **p != '/') (*p)++;
  if (**p == '/') (*p)++;
  return val;
}

// Parse a comma-separated int list field, advance pointer past it.
// Returns count of values parsed.
int parseNextIntList(char** p, int* out, int maxCount) {
  // Find the end of this field (next '/')
  char* start = *p;
  while (**p && **p != '/') (*p)++;
  
  // Temporarily null-terminate
  char saved = **p;
  **p = '\0';
  int count = parseIntList(start, out, maxCount);
  **p = saved;
  
  if (**p == '/') (*p)++;
  return count;
}

#endif
```

- [ ] **Step 2: Add readSerial() to transmitter.ino**

Add after `loop()`:

```cpp
void readSerial() {
  while (Serial.available()) {
    char c = Serial.read();
    
    if (serialPos >= SERIAL_BUF_SIZE - 1) {
      // Buffer overflow — reset
      serialPos = 0;
      continue;
    }
    
    serialBuf[serialPos++] = c;
    serialBuf[serialPos] = '\0';
    
    // Check for complete command (ends with / and has a known prefix)
    if (c == '/' && serialPos >= 2) {
      // Check if this is a complete top-level command
      if (strncmp(serialBuf, "DISC/", 5) == 0) {
        handleDiscovery();
        serialPos = 0;
      } else if (strncmp(serialBuf, "IDENT/", 6) == 0) {
        handleIdentify();
        serialPos = 0;
      } else if (strncmp(serialBuf, "STOP/", 5) == 0) {
        handleStop();
        serialPos = 0;
      } else if (serialBuf[0] == 'A' && serialBuf[1] == '/' && isCommandComplete(serialBuf, 'A')) {
        handleProgramA();
        serialPos = 0;
      } else if (serialBuf[0] == 'B' && serialBuf[1] == '/' && isCommandComplete(serialBuf, 'B')) {
        handleProgramB();
        serialPos = 0;
      }
      // Otherwise keep buffering — command not yet complete
    }
  }
}

// Count slashes to determine if command is complete.
// Program A: A/ + 6 floats/ints + 5 groups + ns + iter = 13 fields = 14 slashes total
// Program B: B/ + 6 floats/ints + targets + ns + iter = 9 fields = 10 slashes total
bool isCommandComplete(const char* buf, char program) {
  int slashes = 0;
  for (int i = 0; buf[i]; i++) {
    if (buf[i] == '/') slashes++;
  }
  if (program == 'A') return slashes >= 14;
  if (program == 'B') return slashes >= 10;
  return false;
}
```

- [ ] **Step 3: Add #include for serial_parser.h at top of transmitter.ino**

Add after the other includes:
```cpp
#include "serial_parser.h"
```

- [ ] **Step 4: Commit**

```bash
git add firmware/transmitter/serial_parser.h firmware/transmitter/transmitter.ino
git commit -m "feat(transmitter): add serial buffer, command parser, and field parsers"
```

### Task 2.3: Discovery and identify handlers

**Files:**
- Modify: `firmware/transmitter/transmitter.ino`

- [ ] **Step 1: Add NRF24 send helper**

```cpp
void sendToTarget(int decimalId, int cmd, int param1, int param2) {
  if (decimalId < 1 || decimalId > MAX_TARGETS) return;
  uint16_t addr = addressMap[decimalId];
  int payload[MSG_SIZE] = {cmd, param1, param2};
  RF24NetworkHeader header(addr);
  network.write(header, &payload, sizeof(payload));
}
```

- [ ] **Step 2: Add handleDiscovery()**

```cpp
void handleDiscovery() {
  for (int id = 1; id <= MAX_TARGETS; id++) {
    sendToTarget(id, CMD_PING, 0, 0);
    
    // Brief wait for response
    unsigned long start = millis();
    bool found = false;
    while (millis() - start < 50) {  // 50ms timeout per target
      network.update();
      if (network.available()) {
        RF24NetworkHeader header;
        int payload[MSG_SIZE] = {0, 0, 0};
        network.read(header, &payload, sizeof(payload));
        if (payload[0] == EVT_PONG) {
          Serial.print("D/");
          Serial.print(id);
          Serial.println("/");
          found = true;
          break;
        }
      }
    }
  }
  Serial.println("DDONE/");
}
```

- [ ] **Step 3: Add handleIdentify()**

```cpp
void handleIdentify() {
  // Parse: IDENT/<addr>/
  char* p = serialBuf + 6; // skip "IDENT/"
  int addr = atoi(p);
  sendToTarget(addr, CMD_IDENTIFY, 0, 0);
}
```

- [ ] **Step 4: Commit**

```bash
git add firmware/transmitter/transmitter.ino
git commit -m "feat(transmitter): add discovery scan and identify commands"
```

### Task 2.4: Program A and B command parsing

**Files:**
- Modify: `firmware/transmitter/transmitter.ino`

- [ ] **Step 1: Add handleProgramA()**

```cpp
void handleProgramA() {
  // A/<startMin>/<startMax>/<delayMin>/<delayMax>/<hitsMin>/<hitsMax>/
  //   <g1>/<g2>/<g3>/<g4>/<g5>/<ns>/<iter>/
  char* p = serialBuf + 2; // skip "A/"
  
  startMin = parseNextFloat(&p);
  startMax = parseNextFloat(&p);
  delayMin = parseNextFloat(&p);
  delayMax = parseNextFloat(&p);
  hitsMin = parseNextInt(&p);
  hitsMax = parseNextInt(&p);
  
  // Parse groups
  activeGroupCount = 0;
  for (int g = 0; g < MAX_GROUPS; g++) {
    int targets[MAX_TARGETS_PER_GROUP];
    int count = parseNextIntList(&p, targets, MAX_TARGETS_PER_GROUP);
    
    if (count == 1 && targets[0] == 0) {
      // Group unused
      groups[g].state = GRP_IDLE;
      groups[g].targetCount = 0;
      continue;
    }
    
    groups[g].targetCount = count;
    for (int i = 0; i < count; i++) {
      groups[g].targets[i] = targets[i];
      groups[g].noShoot[i] = false; // set below
    }
    groups[g].state = GRP_WAITING_START;
    groups[g].iterationsLeft = 0; // set after parsing iter
    groups[g].timerStart = millis();
    // Random start delay
    groups[g].timerDuration = (unsigned long)(randomFloat(startMin, startMax) * 1000.0);
    activeGroupCount++;
  }
  
  // Parse no-shoot list
  noShootCount = parseNextIntList(&p, noShootTargets, MAX_TARGETS);
  
  // Mark no-shoot targets in groups
  for (int g = 0; g < MAX_GROUPS; g++) {
    for (int t = 0; t < groups[g].targetCount; t++) {
      for (int ns = 0; ns < noShootCount; ns++) {
        if (groups[g].targets[t] == noShootTargets[ns]) {
          groups[g].noShoot[t] = true;
        }
      }
    }
  }
  
  // Parse iterations
  iterations = parseNextInt(&p);
  for (int g = 0; g < MAX_GROUPS; g++) {
    if (groups[g].targetCount > 0) {
      groups[g].iterationsLeft = iterations;
    }
  }
  
  drillRunning = true;
  Serial.println("Running Program A");
}

float randomFloat(float minVal, float maxVal) {
  return minVal + (float)random(0, 1000) / 1000.0 * (maxVal - minVal);
}
```

- [ ] **Step 2: Add handleProgramB()**

```cpp
void handleProgramB() {
  // B/<startMin>/<startMax>/<delayMin>/<delayMax>/<hitsMin>/<hitsMax>/
  //   <targets>/<ns>/<iter>/
  char* p = serialBuf + 2; // skip "B/"
  
  startMin = parseNextFloat(&p);
  startMax = parseNextFloat(&p);
  delayMin = parseNextFloat(&p);
  delayMax = parseNextFloat(&p);
  hitsMin = parseNextInt(&p);
  hitsMax = parseNextInt(&p);
  
  // Parse target list
  int allTargets[MAX_TARGETS];
  int totalTargets = parseNextIntList(&p, allTargets, MAX_TARGETS);
  
  // Parse no-shoot list
  noShootCount = parseNextIntList(&p, noShootTargets, MAX_TARGETS);
  
  // Parse iterations
  iterations = parseNextInt(&p);
  
  // Program B: each target is its own group
  activeGroupCount = 0;
  for (int i = 0; i < totalTargets && i < MAX_GROUPS * MAX_TARGETS_PER_GROUP; i++) {
    // Pack targets into groups. If more than MAX_GROUPS targets,
    // we use groups as slots. Each group has exactly 1 target.
    // Note: MAX_GROUPS is 5, but Program B can have up to 30 targets.
    // We need to expand for Program B. For now, reuse groups[] array
    // but treat each slot as a single-target group.
    // Since MAX_GROUPS=5, we need a different approach for >5 targets.
    // SOLUTION: Use groups[] for up to 5, and a flat lane array for Program B.
  }
  
  // Simpler approach: reuse group machinery but cap at 30 lanes
  // We need to increase MAX_GROUPS or use a separate lane array.
  // For now, map each target to a group slot (we need MAX_TARGETS groups for Program B).
  // Revisit: increase groups array or use separate lane struct.
  
  // PRAGMATIC: For Program B, we store all targets in group[0] but with a flag
  // that each operates independently. This requires modifying tickGroups().
  // BETTER: Just allocate groups dynamically.
  
  // CLEANEST: Make groups[] size MAX_TARGETS (30) and set activeGroupCount = totalTargets
  // This wastes memory but ATmega328P has 2KB RAM. GroupState is ~30 bytes.
  // 30 * 30 = 900 bytes. Tight but feasible. Let's do it.
  
  // Actually, we already declared GroupState groups[MAX_GROUPS] with MAX_GROUPS=5.
  // We need to change this. See Task 2.1 config fix below.
  
  // For now, set up as many groups as we have targets (up to 30)
  activeGroupCount = totalTargets;
  for (int i = 0; i < totalTargets; i++) {
    groups[i].targets[0] = allTargets[i];
    groups[i].targetCount = 1;
    groups[i].noShoot[0] = false;
    for (int ns = 0; ns < noShootCount; ns++) {
      if (allTargets[i] == noShootTargets[ns]) {
        groups[i].noShoot[0] = true;
      }
    }
    groups[i].state = GRP_WAITING_START;
    groups[i].iterationsLeft = iterations;
    groups[i].timerStart = millis();
    groups[i].timerDuration = (unsigned long)(randomFloat(startMin, startMax) * 1000.0);
  }
  
  drillRunning = true;
  Serial.println("Running Program B");
}
```

- [ ] **Step 3: Fix MAX_GROUPS in config.h to support Program B**

In `firmware/transmitter/config.h`, change:

```cpp
#define MAX_GROUPS      5
```

to:

```cpp
#define MAX_GROUPS      30  // Program B needs one group per target
```

This costs ~30 bytes * 30 = ~900 bytes of RAM. ATmega328P has 2KB. Tight but workable since we have no large buffers beyond serialBuf (256 bytes). Total: ~1200 bytes used, ~800 bytes free.

- [ ] **Step 4: Commit**

```bash
git add firmware/transmitter/transmitter.ino firmware/transmitter/config.h
git commit -m "feat(transmitter): add Program A and B command parsing"
```

### Task 2.5: Group state machine tick

**Files:**
- Modify: `firmware/transmitter/transmitter.ino`

- [ ] **Step 1: Add tickGroups()**

```cpp
void tickGroups() {
  unsigned long now = millis();
  int doneCount = 0;
  
  for (int g = 0; g < activeGroupCount; g++) {
    GroupState* grp = &groups[g];
    
    switch (grp->state) {
      case GRP_IDLE:
      case GRP_DONE:
        doneCount++;
        break;
        
      case GRP_WAITING_START:
        if (now - grp->timerStart >= grp->timerDuration) {
          grp->state = GRP_SELECT_TARGET;
        }
        break;
        
      case GRP_SELECT_TARGET: {
        // Pick random target from group
        int idx = random(0, grp->targetCount);
        grp->activeTargetIdx = idx;
        grp->activeTargetAddr = grp->targets[idx];
        
        // Random hit count
        grp->requiredHits = random(hitsMin, hitsMax + 1);
        
        // Determine color mode
        int colorMode = grp->noShoot[idx] ? COLOR_NOSHOOT : COLOR_NORMAL;
        
        // Send activate command
        sendToTarget(grp->activeTargetAddr, CMD_ACTIVATE, grp->requiredHits, colorMode);
        
        // Relay to app
        Serial.print("ACT/");
        Serial.print(grp->activeTargetAddr);
        Serial.println("/");
        
        grp->timerStart = now;
        grp->state = GRP_WAITING_COMPLETE;
        
        // For no-shoot targets, set a timer for auto-deactivation
        if (colorMode == COLOR_NOSHOOT) {
          grp->timerDuration = (unsigned long)(randomFloat(delayMin, delayMax) * 1000.0);
        }
        break;
      }
        
      case GRP_WAITING_COMPLETE:
        // For no-shoot targets, deactivate after timer
        if (grp->noShoot[grp->activeTargetIdx]) {
          if (now - grp->timerStart >= grp->timerDuration) {
            sendToTarget(grp->activeTargetAddr, CMD_DEACTIVATE, 0, 0);
            grp->iterationsLeft--;
            if (grp->iterationsLeft <= 0 && iterations > 0) {
              grp->state = GRP_DONE;
            } else {
              grp->timerStart = now;
              grp->timerDuration = (unsigned long)(randomFloat(delayMin, delayMax) * 1000.0);
              grp->state = GRP_WAITING_DELAY;
            }
          }
        }
        // For normal targets, completion is handled in handleNrfEvents()
        break;
        
      case GRP_WAITING_DELAY:
        if (now - grp->timerStart >= grp->timerDuration) {
          grp->state = GRP_SELECT_TARGET;
        }
        break;
    }
  }
  
  // Check if all groups are done
  if (doneCount == activeGroupCount && activeGroupCount > 0) {
    Serial.println("FIN/");
    drillRunning = false;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add firmware/transmitter/transmitter.ino
git commit -m "feat(transmitter): add per-group state machine tick logic"
```

### Task 2.6: NRF24 event handler (target telemetry relay)

**Files:**
- Modify: `firmware/transmitter/transmitter.ino`

- [ ] **Step 1: Add decimal ID lookup from octal address**

```cpp
int octalToDecimalId(uint16_t octalAddr) {
  for (int i = 1; i <= MAX_TARGETS; i++) {
    if (addressMap[i] == octalAddr) return i;
  }
  return 0; // unknown
}
```

- [ ] **Step 2: Add handleNrfEvents()**

```cpp
void handleNrfEvents() {
  while (network.available()) {
    RF24NetworkHeader header;
    int payload[MSG_SIZE] = {0, 0, 0};
    network.read(header, &payload, sizeof(payload));
    
    int decId = octalToDecimalId(header.from_node);
    if (decId == 0) continue; // unknown source
    
    switch (payload[0]) {
      case EVT_PONG:
        // Handled inline during discovery scan
        break;
        
      case EVT_HIT:
        Serial.print("HIT/");
        Serial.print(decId);
        Serial.print("/");
        Serial.print(payload[1]); // hitNumber
        Serial.print("/");
        // Find required hits for this target from its group
        Serial.print(getRequiredHitsForTarget(decId));
        Serial.println("/");
        break;
        
      case EVT_COMPLETE: {
        Serial.print("DONE/");
        Serial.print(decId);
        Serial.print("/");
        Serial.print(payload[2]); // totalTimeMs
        Serial.println("/");
        
        // Advance the group state machine for this target
        for (int g = 0; g < activeGroupCount; g++) {
          if (groups[g].activeTargetAddr == decId && groups[g].state == GRP_WAITING_COMPLETE) {
            groups[g].iterationsLeft--;
            if (groups[g].iterationsLeft <= 0 && iterations > 0) {
              groups[g].state = GRP_DONE;
            } else {
              groups[g].timerStart = millis();
              groups[g].timerDuration = (unsigned long)(randomFloat(delayMin, delayMax) * 1000.0);
              groups[g].state = GRP_WAITING_DELAY;
            }
            break;
          }
        }
        break;
      }
        
      case EVT_NOSHOOT_HIT:
        Serial.print("NS/");
        Serial.print(decId);
        Serial.println("/");
        break;
        
      case EVT_LATE_HIT:
        Serial.print("LATE/");
        Serial.print(decId);
        Serial.println("/");
        break;
    }
  }
}

int getRequiredHitsForTarget(int decId) {
  for (int g = 0; g < activeGroupCount; g++) {
    if (groups[g].activeTargetAddr == decId) {
      return groups[g].requiredHits;
    }
  }
  return 0;
}
```

- [ ] **Step 3: Commit**

```bash
git add firmware/transmitter/transmitter.ino
git commit -m "feat(transmitter): add NRF24 event handler and telemetry relay to app"
```

### Task 2.7: Stop handler

**Files:**
- Modify: `firmware/transmitter/transmitter.ino`

- [ ] **Step 1: Add handleStop()**

```cpp
void handleStop() {
  // Deactivate all targets that are currently in active groups
  for (int g = 0; g < activeGroupCount; g++) {
    if (groups[g].state == GRP_WAITING_COMPLETE) {
      sendToTarget(groups[g].activeTargetAddr, CMD_DEACTIVATE, 0, 0);
    }
    groups[g].state = GRP_IDLE;
    groups[g].targetCount = 0;
  }
  
  activeGroupCount = 0;
  drillRunning = false;
  Serial.println("FIN/");
}
```

- [ ] **Step 2: Verify full transmitter compiles**

Open Arduino IDE, set board to "Arduino Nano" (ATmega328P old bootloader or matching), verify/compile. Expected: clean compile. Check RAM usage — should be under 1800 bytes.

- [ ] **Step 3: Commit**

```bash
git add firmware/transmitter/transmitter.ino
git commit -m "feat(transmitter): add stop handler with target deactivation"
```

### Task 2.8: Integration test with target

- [ ] **Step 1: Flash transmitter**

Upload transmitter.ino to the ATmega328P board with HM-10 and NRF24L01 connected.

- [ ] **Step 2: Flash one target**

Upload target.ino (with `NODE_ADDRESS 01`) to an Arduino Nano target.

- [ ] **Step 3: Test discovery via Serial Monitor**

Connect to transmitter serial at 9600 baud. Type: `DISC/`

Expected output:
```
D/1/
DDONE/
```

- [ ] **Step 4: Test identify**

Type: `IDENT/1/`

Expected: target LED flashes white 3 times.

- [ ] **Step 5: Test a simple drill**

Type: `B/1.00/1.00/1.00/1.00/2/2/1/0/3/`

Expected: target LED turns green. Hit the vibration sensor twice. LED turns off. After 1 second, turns green again. Repeat 3 times. Serial shows `ACT/1/`, `HIT/1/1/2/`, `DONE/1/<time>/`, then eventually `FIN/`.

- [ ] **Step 6: Test stop**

Start a drill, then type `STOP/` before it finishes. Expected: target LED turns off. Serial shows `FIN/`.

---

## Phase 3: Flutter App — Legacy Cleanup and Restructure

Delete legacy code, create the new directory structure, and migrate reusable components. No new features yet — just a clean foundation.

### Task 3.1: Delete legacy files

**Files:**
- Delete: `lib/calculator.dart`
- Delete: `lib/constants.dart`
- Modify: `lib/main.dart` (remove Measure references)

- [ ] **Step 1: Delete calculator.dart and constants.dart**

```bash
git rm lib/calculator.dart lib/constants.dart
```

- [ ] **Step 2: Remove Measure import, button, and dialog from main.dart**

In `lib/main.dart`, remove the import:
```dart
import 'calculator.dart';
```

Remove the entire `_showMeasureDialog()` method (lines 205-315).

Remove the "Measure" button block from the `build` method — the `_buildMenuButton` call with `label: "Measure"` and `description: "Brush pressure measurement"`.

- [ ] **Step 3: Verify the app still compiles**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

Expected: no errors (warnings OK).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove legacy brush pressure measurement code"
```

### Task 3.2: Create directory structure and models

**Files:**
- Create: `lib/services/` directory
- Create: `lib/models/` directory
- Create: `lib/state/` directory
- Create: `lib/screens/` directory (already exists as `lib/Screens/`)
- Create: `lib/models/target_unit.dart`
- Create: `lib/models/target_group.dart`
- Create: `lib/models/drill_config.dart`
- Create: `lib/models/session_event.dart`
- Create: `lib/models/drill_session.dart`

- [ ] **Step 1: Create directories**

```bash
mkdir -p lib/services lib/models lib/state lib/screens
```

- [ ] **Step 2: Create target_unit.dart**

```dart
// lib/models/target_unit.dart

class TargetUnit {
  final int id; // decimal ID 1-30
  bool isOnline;
  int? groupId;
  bool isNoShoot;

  TargetUnit({
    required this.id,
    this.isOnline = false,
    this.groupId,
    this.isNoShoot = false,
  });
}
```

- [ ] **Step 3: Create target_group.dart**

```dart
// lib/models/target_group.dart

class TargetGroup {
  final int id; // 1-5
  String name;
  List<int> targetIds; // decimal IDs of targets in this group

  TargetGroup({
    required this.id,
    String? name,
    List<int>? targetIds,
  })  : name = name ?? 'Group $id',
        targetIds = targetIds ?? [];
}
```

- [ ] **Step 4: Create drill_config.dart**

```dart
// lib/models/drill_config.dart

import 'target_group.dart';

enum ProgramType { programA, programB }

class DrillConfig {
  ProgramType programType;
  double startMin;
  double startMax;
  double delayMin;
  double delayMax;
  int hitsMin;
  int hitsMax;
  List<TargetGroup> groups; // Program A
  List<int> targetIds;      // Program B
  List<int> noShootIds;
  int iterations;

  DrillConfig({
    required this.programType,
    this.startMin = 1.0,
    this.startMax = 3.0,
    this.delayMin = 0.5,
    this.delayMax = 2.0,
    this.hitsMin = 1,
    this.hitsMax = 3,
    List<TargetGroup>? groups,
    List<int>? targetIds,
    List<int>? noShootIds,
    this.iterations = 5,
  })  : groups = groups ?? [],
        targetIds = targetIds ?? [],
        noShootIds = noShootIds ?? [];
}
```

- [ ] **Step 5: Create session_event.dart**

```dart
// lib/models/session_event.dart

enum EventType {
  targetActivated,
  hitDetected,
  targetComplete,
  noShootViolation,
  lateHit,
  drillFinished,
  error,
}

class SessionEvent {
  final EventType type;
  final int? targetId;
  final int? hitNumber;
  final int? requiredHits;
  final int? totalTimeMs;
  final String? errorDetail;
  final DateTime timestamp;

  SessionEvent({
    required this.type,
    this.targetId,
    this.hitNumber,
    this.requiredHits,
    this.totalTimeMs,
    this.errorDetail,
  }) : timestamp = DateTime.now();
}
```

- [ ] **Step 6: Create drill_session.dart**

```dart
// lib/models/drill_session.dart

import 'session_event.dart';
import 'drill_config.dart';

class DrillSession {
  final DrillConfig config;
  final List<SessionEvent> events;
  final DateTime startTime;
  DateTime? endTime;
  bool isRunning;

  DrillSession({
    required this.config,
  })  : events = [],
        startTime = DateTime.now(),
        isRunning = true;

  void addEvent(SessionEvent event) {
    events.add(event);
    if (event.type == EventType.drillFinished) {
      isRunning = false;
      endTime = DateTime.now();
    }
  }

  Duration get elapsed => (endTime ?? DateTime.now()).difference(startTime);
}
```

- [ ] **Step 7: Verify models compile**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

- [ ] **Step 8: Commit**

```bash
git add lib/models/ lib/services/ lib/state/ lib/screens/
git commit -m "feat: add data models for targets, groups, drill config, and session events"
```

### Task 3.3: Create transmitter protocol service

**Files:**
- Create: `lib/services/transmitter_protocol.dart`

- [ ] **Step 1: Create transmitter_protocol.dart**

```dart
// lib/services/transmitter_protocol.dart

import '../models/drill_config.dart';
import '../models/session_event.dart';

class TransmitterProtocol {
  // --- Encoding: App -> Transmitter ---

  static String encodeDiscovery() => 'DISC/';

  static String encodeIdentify(int targetId) => 'IDENT/$targetId/';

  static String encodeStop() => 'STOP/';

  static String encodeDrillStart(DrillConfig config) {
    if (config.programType == ProgramType.programA) {
      return _encodeProgramA(config);
    } else {
      return _encodeProgramB(config);
    }
  }

  static String _encodeProgramA(DrillConfig config) {
    final buf = StringBuffer('A/');
    buf.write('${config.startMin}/${config.startMax}/');
    buf.write('${config.delayMin}/${config.delayMax}/');
    buf.write('${config.hitsMin}/${config.hitsMax}/');

    // Groups 1-5
    for (int g = 0; g < 5; g++) {
      if (g < config.groups.length && config.groups[g].targetIds.isNotEmpty) {
        buf.write(config.groups[g].targetIds.join(','));
      } else {
        buf.write('0');
      }
      buf.write('/');
    }

    // No-shoot list
    if (config.noShootIds.isNotEmpty) {
      buf.write(config.noShootIds.join(','));
    } else {
      buf.write('0');
    }
    buf.write('/');

    // Iterations
    buf.write('${config.iterations}/');

    return buf.toString();
  }

  static String _encodeProgramB(DrillConfig config) {
    final buf = StringBuffer('B/');
    buf.write('${config.startMin}/${config.startMax}/');
    buf.write('${config.delayMin}/${config.delayMax}/');
    buf.write('${config.hitsMin}/${config.hitsMax}/');

    // Targets
    buf.write(config.targetIds.join(','));
    buf.write('/');

    // No-shoot list
    if (config.noShootIds.isNotEmpty) {
      buf.write(config.noShootIds.join(','));
    } else {
      buf.write('0');
    }
    buf.write('/');

    // Iterations
    buf.write('${config.iterations}/');

    return buf.toString();
  }

  // --- Decoding: Transmitter -> App ---

  static dynamic decodeTelemetry(String message) {
    final msg = message.trim();

    if (msg.startsWith('D/') && msg != 'DDONE/') {
      final parts = msg.split('/');
      final id = int.tryParse(parts[1]);
      if (id != null) return DiscoveredTarget(id);
    }

    if (msg == 'DDONE/') return DiscoveryDone();

    if (msg.startsWith('ACT/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.targetActivated,
        targetId: int.tryParse(parts[1]),
      );
    }

    if (msg.startsWith('HIT/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.hitDetected,
        targetId: int.tryParse(parts[1]),
        hitNumber: int.tryParse(parts[2]),
        requiredHits: int.tryParse(parts[3]),
      );
    }

    if (msg.startsWith('DONE/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.targetComplete,
        targetId: int.tryParse(parts[1]),
        totalTimeMs: int.tryParse(parts[2]),
      );
    }

    if (msg.startsWith('NS/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.noShootViolation,
        targetId: int.tryParse(parts[1]),
      );
    }

    if (msg.startsWith('LATE/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.lateHit,
        targetId: int.tryParse(parts[1]),
      );
    }

    if (msg == 'FIN/') {
      return SessionEvent(type: EventType.drillFinished);
    }

    if (msg.startsWith('ERR/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.error,
        errorDetail: parts.sublist(1).join('/'),
      );
    }

    return null; // Unknown message
  }
}

// Helper classes for discovery messages
class DiscoveredTarget {
  final int id;
  DiscoveredTarget(this.id);
}

class DiscoveryDone {}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add lib/services/transmitter_protocol.dart
git commit -m "feat: add transmitter protocol encoder/decoder"
```

### Task 3.4: Create BLE service

**Files:**
- Create: `lib/services/ble_service.dart`

- [ ] **Step 1: Create ble_service.dart**

```dart
// lib/services/ble_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String characteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  final _connectionController = StreamController<BluetoothConnectionState>.broadcast();
  final _dataController = StreamController<String>.broadcast();

  Stream<BluetoothConnectionState> get connectionState => _connectionController.stream;
  Stream<String> get incomingData => _dataController.stream;

  BluetoothDevice? get device => _device;
  bool get isConnected => _characteristic != null;

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect();

    _connectionSub = device.connectionState.listen((state) {
      _connectionController.add(state);
      if (state == BluetoothConnectionState.disconnected) {
        _characteristic = null;
      }
    });

    // Discover services
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid.toString() == serviceUuid) {
        for (final char in service.characteristics) {
          if (char.uuid.toString() == characteristicUuid) {
            _characteristic = char;
            await _startNotifications();
            return;
          }
        }
      }
    }
    throw Exception('Required BLE service/characteristic not found');
  }

  Future<void> _startNotifications() async {
    if (_characteristic == null) return;
    await _characteristic!.setNotifyValue(true);

    String buffer = '';
    _notifySub = _characteristic!.onValueReceived.listen((bytes) {
      buffer += utf8.decode(bytes);
      // Split on newlines or parse complete messages ending with /
      while (buffer.contains('\n')) {
        final idx = buffer.indexOf('\n');
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        if (line.isNotEmpty) _dataController.add(line);
      }
      // Also check for messages terminated by / without newline
      // The transmitter prints each message with println, so \n is the delimiter
    });
  }

  Future<void> write(String message) async {
    if (_characteristic == null) throw Exception('Not connected');
    final bytes = utf8.encode(message);
    await _characteristic!.write(bytes);
  }

  Future<void> disconnect() async {
    _notifySub?.cancel();
    _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _characteristic = null;
  }

  void dispose() {
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _connectionController.close();
    _dataController.close();
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add lib/services/ble_service.dart
git commit -m "feat: add BLE service with connection management and notification streaming"
```

### Task 3.5: Create app state

**Files:**
- Create: `lib/state/app_state.dart`

- [ ] **Step 1: Create app_state.dart**

```dart
// lib/state/app_state.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/ble_service.dart';
import '../services/transmitter_protocol.dart';
import '../models/target_unit.dart';
import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';

class AppState extends ChangeNotifier {
  final BleService bleService = BleService();

  // Discovered targets from NRF24 scan
  List<TargetUnit> targets = [];
  bool isScanning = false;

  // Current drill
  DrillSession? currentSession;

  StreamSubscription<String>? _dataSub;

  AppState() {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
  }

  void _handleIncomingData(String message) {
    final decoded = TransmitterProtocol.decodeTelemetry(message);

    if (decoded is DiscoveredTarget) {
      final existing = targets.where((t) => t.id == decoded.id);
      if (existing.isEmpty) {
        targets.add(TargetUnit(id: decoded.id, isOnline: true));
      } else {
        existing.first.isOnline = true;
      }
      notifyListeners();
      return;
    }

    if (decoded is DiscoveryDone) {
      isScanning = false;
      notifyListeners();
      return;
    }

    if (decoded is SessionEvent && currentSession != null) {
      currentSession!.addEvent(decoded);
      notifyListeners();
    }
  }

  Future<void> discoverTargets() async {
    isScanning = true;
    // Mark all targets offline before scan
    for (final t in targets) {
      t.isOnline = false;
    }
    notifyListeners();
    await bleService.write(TransmitterProtocol.encodeDiscovery());
  }

  Future<void> identifyTarget(int targetId) async {
    await bleService.write(TransmitterProtocol.encodeIdentify(targetId));
  }

  Future<void> startDrill(DrillConfig config) async {
    currentSession = DrillSession(config: config);
    notifyListeners();
    await bleService.write(TransmitterProtocol.encodeDrillStart(config));
  }

  Future<void> stopDrill() async {
    await bleService.write(TransmitterProtocol.encodeStop());
    // The FIN/ message from transmitter will end the session
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    bleService.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: Add provider dependency to pubspec.yaml**

In `pubspec.yaml`, add under `dependencies:`:
```yaml
  provider: ^6.1.0
```

Run:
```bash
cd /Volumes/T7/Atriarch && flutter pub get
```

- [ ] **Step 3: Verify it compiles**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add lib/state/app_state.dart pubspec.yaml pubspec.lock
git commit -m "feat: add AppState with BLE data handling, discovery, and drill management"
```

### Task 3.6: Rewrite main.dart with Provider and clean routing

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Rewrite main.dart**

```dart
// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'state/app_state.dart';
import 'screens/device_discovery_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const AtriarchApp(),
    ),
  );
}

class AtriarchApp extends StatelessWidget {
  const AtriarchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atriarch',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: StreamBuilder<BluetoothAdapterState>(
        stream: FlutterBluePlus.adapterState,
        initialData: BluetoothAdapterState.unknown,
        builder: (context, snapshot) {
          if (snapshot.data == BluetoothAdapterState.on) {
            return const DeviceDiscoveryScreen();
          }
          return const BluetoothOffScreen();
        },
      ),
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled, size: 100, color: Colors.grey),
            SizedBox(height: 16),
            Text('Please enable Bluetooth', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles** (will have error for missing DeviceDiscoveryScreen — expected)

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "refactor: rewrite main.dart with Provider and clean routing"
```

### Task 3.7: Device discovery screen

**Files:**
- Create: `lib/screens/device_discovery_screen.dart`

- [ ] **Step 1: Create device_discovery_screen.dart**

```dart
// lib/screens/device_discovery_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'home_screen.dart';

class DeviceDiscoveryScreen extends StatefulWidget {
  const DeviceDiscoveryScreen({super.key});

  @override
  State<DeviceDiscoveryScreen> createState() => _DeviceDiscoveryScreenState();
}

class _DeviceDiscoveryScreenState extends State<DeviceDiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
  }

  void _connectAndNavigate(BluetoothDevice device) async {
    final appState = context.read<AppState>();
    try {
      await appState.bleService.connect(device);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Transmitter')),
      body: RefreshIndicator(
        onRefresh: () => FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)),
        child: StreamBuilder<List<ScanResult>>(
          stream: FlutterBluePlus.scanResults,
          initialData: const [],
          builder: (context, snapshot) {
            final results = snapshot.data ?? [];
            if (results.isEmpty) {
              return const Center(child: Text('Scanning for devices...'));
            }
            return ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final r = results[index];
                final name = r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : r.device.remoteId.toString();
                return ListTile(
                  title: Text(name),
                  subtitle: Text(r.device.remoteId.toString()),
                  trailing: Text('${r.rssi} dBm'),
                  onTap: r.advertisementData.connectable
                      ? () => _connectAndNavigate(r.device)
                      : null,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBluePlus.isScanning,
        initialData: false,
        builder: (context, snapshot) {
          return FloatingActionButton(
            onPressed: snapshot.data!
                ? FlutterBluePlus.stopScan
                : () => FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)),
            child: Icon(snapshot.data! ? Icons.stop : Icons.search),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Create placeholder home_screen.dart**

```dart
// lib/screens/home_screen.dart

import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atriarch')),
      body: const Center(child: Text('Connected! Home screen coming soon.')),
    );
  }
}
```

- [ ] **Step 3: Delete old screen files**

```bash
git rm lib/Screens/ProgramA.dart lib/Screens/ProgramB.dart
rm -rf lib/Screens  # remove old capitalized directory
```

- [ ] **Step 4: Clean up unused widgets**

Delete the legacy BLE debug widgets from `lib/widgets.dart`. Keep only `ScanResultTile` if desired, or delete the whole file since we've replaced it with inline ListView in the discovery screen.

```bash
git rm lib/widgets.dart
```

- [ ] **Step 5: Move and rename IncDec widget**

```bash
mv lib/widgets/IncDec.dart lib/widgets/inc_dec.dart
git rm lib/widgets/TextWidget.dart
```

Update the import path in `lib/widgets/inc_dec.dart` if needed (it has no internal imports that need changing).

- [ ] **Step 6: Verify the app compiles and runs**

```bash
cd /Volumes/T7/Atriarch && flutter analyze && flutter build apk --debug
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: replace legacy screens with clean app shell and device discovery"
```

### Task 3.8: Update pubspec.yaml and README

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`

- [ ] **Step 1: Update pubspec.yaml description**

Change:
```yaml
description: ESP32 BLE Spring Test App for iOS and Android
```
to:
```yaml
description: Atriarch - Wireless Reactive Target Training System
```

- [ ] **Step 2: Rewrite README.md**

```markdown
# Atriarch

Wireless reactive target training system for shooting, reaction, law enforcement, and competition-style drills.

## Architecture

- **Flutter App** (iOS/Android) — drill configuration, timer, post-drill results
- **Transmitter** (ATmega328P + HM-10 BLE + NRF24L01) — drill orchestration
- **Targets** (Arduino Nano + NRF24L01 + WS2812 + vibration sensor) — up to 30 units

See `docs/superpowers/specs/` for the full system design spec.

## Development

```bash
flutter pub get
flutter run
```

Firmware is in `firmware/target/` and `firmware/transmitter/`. Open in Arduino IDE.
```

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml README.md
git commit -m "docs: update project description and README for target training system"
```

---

## Phase 4: Flutter App — Screens and Features

Build out the remaining screens: target discovery, program setup, drill running, and results.

### Task 4.1: Target discovery screen

**Files:**
- Create: `lib/screens/target_discovery_screen.dart`
- Create: `lib/widgets/target_chip.dart`

- [ ] **Step 1: Create target_chip.dart**

```dart
// lib/widgets/target_chip.dart

import 'package:flutter/material.dart';
import '../models/target_unit.dart';

class TargetChip extends StatelessWidget {
  final TargetUnit target;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TargetChip({
    super.key,
    required this.target,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Chip(
        label: Text('T${target.id}'),
        backgroundColor: _color(),
        side: selected ? const BorderSide(color: Colors.blue, width: 2) : null,
      ),
    );
  }

  Color _color() {
    if (!target.isOnline) return Colors.grey.shade300;
    if (target.isNoShoot) return Colors.red.shade100;
    if (target.groupId != null) return Colors.green.shade100;
    return Colors.white;
  }
}
```

- [ ] **Step 2: Create target_discovery_screen.dart**

```dart
// lib/screens/target_discovery_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/target_chip.dart';

class TargetDiscoveryScreen extends StatelessWidget {
  const TargetDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Target Setup'),
        actions: [
          Consumer<AppState>(
            builder: (_, state, __) => IconButton(
              icon: state.isScanning
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh),
              onPressed: state.isScanning ? null : () => state.discoverTargets(),
            ),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          final onlineTargets = state.targets.where((t) => t.isOnline).toList();
          if (onlineTargets.isEmpty && !state.isScanning) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No targets found.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => state.discoverTargets(),
                    child: const Text('Scan for Targets'),
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${onlineTargets.length} target(s) online',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: onlineTargets.map((t) => TargetChip(
                    target: t,
                    onTap: () => state.identifyTarget(t.id),
                    onLongPress: () => _showTargetOptions(context, t, state),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Tap to flash LED. Long-press for options.',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTargetOptions(BuildContext context, target, AppState state) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('Identify (flash LED)'),
              onTap: () {
                state.identifyTarget(target.id);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                target.isNoShoot ? Icons.gpp_good : Icons.gpp_bad,
              ),
              title: Text(target.isNoShoot ? 'Remove No-Shoot' : 'Mark as No-Shoot'),
              onTap: () {
                target.isNoShoot = !target.isNoShoot;
                state.notifyListeners();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/target_discovery_screen.dart lib/widgets/target_chip.dart
git commit -m "feat: add target discovery screen with identify and no-shoot toggle"
```

### Task 4.2: Home screen with navigation

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Rewrite home_screen.dart with real navigation**

```dart
// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'device_discovery_screen.dart';
import 'target_discovery_screen.dart';
import 'program_a_setup_screen.dart';
import 'program_b_setup_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atriarch'),
        leading: IconButton(
          icon: const Icon(Icons.bluetooth_disabled),
          onPressed: () async {
            final state = context.read<AppState>();
            await state.bleService.disconnect();
            if (context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DeviceDiscoveryScreen()),
              );
            }
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 120, height: 120,
                child: Image(image: AssetImage('assets/logo.png')),
              ),
              const SizedBox(height: 40),
              _MenuButton(
                label: 'Target Setup',
                icon: Icons.track_changes,
                color: Colors.teal,
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TargetDiscoveryScreen())),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Program A — Group Mode',
                icon: Icons.group,
                color: Colors.blue,
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProgramASetupScreen())),
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'Program B — Individual Mode',
                icon: Icons.person,
                color: Colors.deepPurple,
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProgramBSetupScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _MenuButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(fontSize: 16, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
```

- [ ] **Step 2: Create placeholder screens for Program A and B**

```dart
// lib/screens/program_a_setup_screen.dart

import 'package:flutter/material.dart';

class ProgramASetupScreen extends StatelessWidget {
  const ProgramASetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Program A — Group Mode')),
      body: const Center(child: Text('Program A setup coming next.')),
    );
  }
}
```

```dart
// lib/screens/program_b_setup_screen.dart

import 'package:flutter/material.dart';

class ProgramBSetupScreen extends StatelessWidget {
  const ProgramBSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Program B — Individual Mode')),
      body: const Center(child: Text('Program B setup coming next.')),
    );
  }
}
```

- [ ] **Step 3: Verify the app compiles and runs**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/
git commit -m "feat: add home screen with navigation to target setup and program screens"
```

### Task 4.3: Program B setup screen (simpler — build first)

**Files:**
- Modify: `lib/screens/program_b_setup_screen.dart`

- [ ] **Step 1: Rewrite program_b_setup_screen.dart**

```dart
// lib/screens/program_b_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/drill_config.dart';
import '../widgets/inc_dec.dart';
import 'drill_running_screen.dart';

class ProgramBSetupScreen extends StatefulWidget {
  const ProgramBSetupScreen({super.key});

  @override
  State<ProgramBSetupScreen> createState() => _ProgramBSetupScreenState();
}

class _ProgramBSetupScreenState extends State<ProgramBSetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1.00');
  final hitsMaxCtrl = TextEditingController(text: '3.00');
  final iterCtrl = TextEditingController(text: '5.00');

  void _startDrill() {
    final state = context.read<AppState>();
    final onlineTargets = state.targets.where((t) => t.isOnline).toList();

    if (onlineTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No targets online. Run Target Setup first.')),
      );
      return;
    }

    final config = DrillConfig(
      programType: ProgramType.programB,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: (double.tryParse(hitsMinCtrl.text) ?? 1).toInt(),
      hitsMax: (double.tryParse(hitsMaxCtrl.text) ?? 3).toInt(),
      targetIds: onlineTargets.map((t) => t.id).toList(),
      noShootIds: onlineTargets.where((t) => t.isNoShoot).map((t) => t.id).toList(),
      iterations: (double.tryParse(iterCtrl.text) ?? 5).toInt(),
    );

    state.startDrill(config);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DrillRunningScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Program B — Individual Mode')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _sectionLabel('Start Delay (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(startMinCtrl, 'Min', 0.25),
                IncDec(startMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Time Between Activations (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(delayMinCtrl, 'Min', 0.25),
                IncDec(delayMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Required Hits'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(hitsMinCtrl, 'Min'),
                IncDec(hitsMaxCtrl, 'Max'),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Iterations per Target'),
            Center(child: IncDec(iterCtrl, 'Count')),
            const SizedBox(height: 16),
            Consumer<AppState>(
              builder: (_, state, __) {
                final online = state.targets.where((t) => t.isOnline).length;
                final noShoot = state.targets.where((t) => t.isOnline && t.isNoShoot).length;
                return Text('$online target(s) online, $noShoot no-shoot',
                    style: const TextStyle(color: Colors.grey));
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _startDrill,
                child: const Text('START DRILL',
                    style: TextStyle(fontSize: 20, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/program_b_setup_screen.dart
git commit -m "feat: add Program B setup screen with drill configuration"
```

### Task 4.4: Program A setup screen

**Files:**
- Modify: `lib/screens/program_a_setup_screen.dart`

- [ ] **Step 1: Rewrite program_a_setup_screen.dart**

```dart
// lib/screens/program_a_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/drill_config.dart';
import '../models/target_group.dart';
import '../widgets/inc_dec.dart';
import '../widgets/target_chip.dart';
import 'drill_running_screen.dart';

class ProgramASetupScreen extends StatefulWidget {
  const ProgramASetupScreen({super.key});

  @override
  State<ProgramASetupScreen> createState() => _ProgramASetupScreenState();
}

class _ProgramASetupScreenState extends State<ProgramASetupScreen> {
  final startMinCtrl = TextEditingController(text: '1.00');
  final startMaxCtrl = TextEditingController(text: '3.00');
  final delayMinCtrl = TextEditingController(text: '0.50');
  final delayMaxCtrl = TextEditingController(text: '2.00');
  final hitsMinCtrl = TextEditingController(text: '1.00');
  final hitsMaxCtrl = TextEditingController(text: '3.00');
  final iterCtrl = TextEditingController(text: '5.00');

  List<TargetGroup> groups = List.generate(5, (i) => TargetGroup(id: i + 1));
  int? selectedGroupIndex;

  void _startDrill() {
    final state = context.read<AppState>();

    final activeGroups = groups.where((g) => g.targetIds.isNotEmpty).toList();
    if (activeGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assign at least one target to a group.')),
      );
      return;
    }

    // Collect no-shoot IDs from targets
    final noShootIds = state.targets
        .where((t) => t.isOnline && t.isNoShoot)
        .map((t) => t.id)
        .toList();

    final config = DrillConfig(
      programType: ProgramType.programA,
      startMin: double.tryParse(startMinCtrl.text) ?? 1.0,
      startMax: double.tryParse(startMaxCtrl.text) ?? 3.0,
      delayMin: double.tryParse(delayMinCtrl.text) ?? 0.5,
      delayMax: double.tryParse(delayMaxCtrl.text) ?? 2.0,
      hitsMin: (double.tryParse(hitsMinCtrl.text) ?? 1).toInt(),
      hitsMax: (double.tryParse(hitsMaxCtrl.text) ?? 3).toInt(),
      groups: groups,
      noShootIds: noShootIds,
      iterations: (double.tryParse(iterCtrl.text) ?? 5).toInt(),
    );

    state.startDrill(config);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DrillRunningScreen()),
    );
  }

  void _assignTargetToGroup(int targetId) {
    if (selectedGroupIndex == null) return;
    setState(() {
      // Remove from any other group
      for (final g in groups) {
        g.targetIds.remove(targetId);
      }
      groups[selectedGroupIndex!].targetIds.add(targetId);
    });
  }

  void _removeTargetFromGroup(int groupIndex, int targetId) {
    setState(() {
      groups[groupIndex].targetIds.remove(targetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Program A — Group Mode')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timing config
            _sectionLabel('Start Delay (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(startMinCtrl, 'Min', 0.25),
                IncDec(startMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Time Between Activations (seconds)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(delayMinCtrl, 'Min', 0.25),
                IncDec(delayMaxCtrl, 'Max', 0.25),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Required Hits'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IncDec(hitsMinCtrl, 'Min'),
                IncDec(hitsMaxCtrl, 'Max'),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('Iterations per Group'),
            Center(child: IncDec(iterCtrl, 'Count')),

            const SizedBox(height: 32),
            _sectionLabel('Group Assignment'),
            const Text('Select a group, then tap online targets to assign them.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),

            // Group tabs
            ...List.generate(5, (i) => _buildGroupSection(i)),

            const SizedBox(height: 16),
            // Unassigned targets
            _sectionLabel('Available Targets'),
            Consumer<AppState>(
              builder: (_, state, __) {
                final assigned = groups.expand((g) => g.targetIds).toSet();
                final unassigned = state.targets
                    .where((t) => t.isOnline && !assigned.contains(t.id))
                    .toList();
                if (unassigned.isEmpty) {
                  return const Text('All online targets assigned.',
                      style: TextStyle(color: Colors.grey));
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: unassigned.map((t) => TargetChip(
                    target: t,
                    onTap: () => _assignTargetToGroup(t.id),
                  )).toList(),
                );
              },
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _startDrill,
                child: const Text('START DRILL',
                    style: TextStyle(fontSize: 20, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSection(int index) {
    final group = groups[index];
    final isSelected = selectedGroupIndex == index;
    return Card(
      color: isSelected ? Colors.blue.shade50 : null,
      child: InkWell(
        onTap: () => setState(() => selectedGroupIndex = index),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Group ${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.blue : null,
                  )),
              const SizedBox(height: 8),
              group.targetIds.isEmpty
                  ? const Text('No targets assigned', style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 4,
                      children: group.targetIds.map((id) => Chip(
                        label: Text('T$id'),
                        onDeleted: () => _removeTargetFromGroup(index, id),
                        deleteIconColor: Colors.red,
                      )).toList(),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/program_a_setup_screen.dart
git commit -m "feat: add Program A setup screen with group assignment UI"
```

### Task 4.5: Drill running screen

**Files:**
- Create: `lib/screens/drill_running_screen.dart`
- Create: `lib/widgets/drill_timer.dart`

- [ ] **Step 1: Create drill_timer.dart**

```dart
// lib/widgets/drill_timer.dart

import 'dart:async';
import 'package:flutter/material.dart';

class DrillTimer extends StatefulWidget {
  const DrillTimer({super.key});

  @override
  State<DrillTimer> createState() => _DrillTimerState();
}

class _DrillTimerState extends State<DrillTimer> {
  final _stopwatch = Stopwatch()..start();
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenths = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$minutes:$seconds.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(_stopwatch.elapsed),
      style: const TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w300,
        fontFamily: 'monospace',
      ),
    );
  }
}
```

- [ ] **Step 2: Create drill_running_screen.dart**

```dart
// lib/screens/drill_running_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/session_event.dart';
import '../widgets/drill_timer.dart';
import 'results_screen.dart';
import 'home_screen.dart';

class DrillRunningScreen extends StatefulWidget {
  const DrillRunningScreen({super.key});

  @override
  State<DrillRunningScreen> createState() => _DrillRunningScreenState();
}

class _DrillRunningScreenState extends State<DrillRunningScreen> {
  @override
  void initState() {
    super.initState();
    // Listen for drill completion
    final state = context.read<AppState>();
    state.addListener(_checkDrillComplete);
  }

  @override
  void dispose() {
    final state = context.read<AppState>();
    state.removeListener(_checkDrillComplete);
    super.dispose();
  }

  void _checkDrillComplete() {
    final state = context.read<AppState>();
    if (state.currentSession != null && !state.currentSession!.isRunning) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResultsScreen()),
      );
    }
  }

  void _stopDrill() async {
    final state = context.read<AppState>();
    await state.stopDrill();
    // FIN/ from transmitter will trigger navigation via _checkDrillComplete
    // But if BLE fails, navigate directly after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && state.currentSession?.isRunning == true) {
        state.currentSession!.addEvent(SessionEvent(type: EventType.drillFinished));
        state.notifyListeners();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back button during drill
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('DRILL ACTIVE',
                  style: TextStyle(color: Colors.green, fontSize: 24,
                      fontWeight: FontWeight.bold, letterSpacing: 4)),
              const SizedBox(height: 40),
              const DrillTimer(),
              const SizedBox(height: 60),
              SizedBox(
                width: 200,
                height: 200,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: const CircleBorder(),
                  ),
                  onPressed: _stopDrill,
                  child: const Text('STOP',
                      style: TextStyle(fontSize: 32, color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Create placeholder results_screen.dart**

```dart
// lib/screens/results_screen.dart

import 'package:flutter/material.dart';
import 'home_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drill Results')),
      body: const Center(child: Text('Results coming next.')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        ),
        child: const Icon(Icons.home),
      ),
    );
  }
}
```

- [ ] **Step 4: Verify the full app compiles**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/drill_running_screen.dart lib/screens/results_screen.dart lib/widgets/drill_timer.dart
git commit -m "feat: add drill running screen (timer + stop) and results placeholder"
```

### Task 4.6: Results screen

**Files:**
- Modify: `lib/screens/results_screen.dart`

- [ ] **Step 1: Rewrite results_screen.dart with full telemetry display**

```dart
// lib/screens/results_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/session_event.dart';
import 'home_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final session = state.currentSession;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const Center(child: Text('No session data.')),
      );
    }

    final events = session.events;
    final activations = events.where((e) => e.type == EventType.targetActivated).toList();
    final completions = events.where((e) => e.type == EventType.targetComplete).toList();
    final noShoots = events.where((e) => e.type == EventType.noShootViolation).toList();
    final lateHits = events.where((e) => e.type == EventType.lateHit).toList();
    final hits = events.where((e) => e.type == EventType.hitDetected).toList();

    // Per-target stats
    final targetIds = activations.map((e) => e.targetId).whereType<int>().toSet();
    final perTarget = <int, _TargetStats>{};
    for (final id in targetIds) {
      final tActivations = activations.where((e) => e.targetId == id).length;
      final tCompletions = completions.where((e) => e.targetId == id).toList();
      final tHits = hits.where((e) => e.targetId == id).length;
      final tNoShoots = noShoots.where((e) => e.targetId == id).length;
      final tLateHits = lateHits.where((e) => e.targetId == id).length;
      final avgTime = tCompletions.isNotEmpty
          ? tCompletions.map((e) => e.totalTimeMs ?? 0).reduce((a, b) => a + b) / tCompletions.length
          : 0.0;
      perTarget[id] = _TargetStats(
        activations: tActivations,
        completions: tCompletions.length,
        hits: tHits,
        noShoots: tNoShoots,
        lateHits: tLateHits,
        avgCompletionMs: avgTime,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Drill Results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard('Duration', _formatDuration(session.elapsed)),
                _StatCard('Activations', '${activations.length}'),
                _StatCard('Total Hits', '${hits.length}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard('Completions', '${completions.length}', color: Colors.green),
                _StatCard('No-Shoot', '${noShoots.length}',
                    color: noShoots.isEmpty ? Colors.green : Colors.red),
                _StatCard('Late Hits', '${lateHits.length}',
                    color: lateHits.isEmpty ? Colors.green : Colors.orange),
              ],
            ),

            const SizedBox(height: 24),
            const Text('Per-Target Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // Per-target table
            DataTable(
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Target')),
                DataColumn(label: Text('Hits')),
                DataColumn(label: Text('Done')),
                DataColumn(label: Text('Avg ms')),
                DataColumn(label: Text('NS')),
                DataColumn(label: Text('Late')),
              ],
              rows: perTarget.entries.map((entry) {
                final s = entry.value;
                return DataRow(cells: [
                  DataCell(Text('T${entry.key}')),
                  DataCell(Text('${s.hits}')),
                  DataCell(Text('${s.completions}')),
                  DataCell(Text('${s.avgCompletionMs.toInt()}')),
                  DataCell(Text('${s.noShoots}',
                      style: TextStyle(color: s.noShoots > 0 ? Colors.red : null))),
                  DataCell(Text('${s.lateHits}',
                      style: TextStyle(color: s.lateHits > 0 ? Colors.orange : null))),
                ]);
              }).toList(),
            ),

            const SizedBox(height: 24),
            const Text('Event Log',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...events.map((e) => _EventTile(event: e)),
            const SizedBox(height: 32),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        ),
        child: const Icon(Icons.home),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }
}

class _TargetStats {
  final int activations;
  final int completions;
  final int hits;
  final int noShoots;
  final int lateHits;
  final double avgCompletionMs;

  _TargetStats({
    required this.activations,
    required this.completions,
    required this.hits,
    required this.noShoots,
    required this.lateHits,
    required this.avgCompletionMs,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatCard(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SessionEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String text;

    switch (event.type) {
      case EventType.targetActivated:
        icon = Icons.play_arrow;
        color = Colors.green;
        text = 'Target ${event.targetId} activated';
      case EventType.hitDetected:
        icon = Icons.gps_fixed;
        color = Colors.blue;
        text = 'Target ${event.targetId} hit ${event.hitNumber}/${event.requiredHits}';
      case EventType.targetComplete:
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'Target ${event.targetId} complete (${event.totalTimeMs}ms)';
      case EventType.noShootViolation:
        icon = Icons.warning;
        color = Colors.red;
        text = 'NO-SHOOT Target ${event.targetId}!';
      case EventType.lateHit:
        icon = Icons.timer_off;
        color = Colors.orange;
        text = 'Late hit on Target ${event.targetId}';
      case EventType.drillFinished:
        icon = Icons.flag;
        color = Colors.grey;
        text = 'Drill finished';
      case EventType.error:
        icon = Icons.error;
        color = Colors.red;
        text = 'Error: ${event.errorDetail}';
    }

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(text, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        '${event.timestamp.hour}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify the full app compiles**

```bash
cd /Volumes/T7/Atriarch && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/results_screen.dart
git commit -m "feat: add results screen with per-target stats, violations, and event log"
```

---

## Phase Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| **1: Target Firmware** | 1.1–1.6 | Flashable target with full state machine (IDLE, ACTIVE, COOLDOWN, IDENTIFY) |
| **2: Transmitter Firmware** | 2.1–2.8 | Flashable transmitter parsing A/B/STOP/DISC/IDENT, orchestrating groups, relaying telemetry |
| **3: App Cleanup** | 3.1–3.8 | Clean app shell: models, services, BLE, state management, no legacy code |
| **4: App Screens** | 4.1–4.6 | Full UI: target discovery, group assignment, program setup, drill timer, results |

**Phases 1+2 (firmware) and 3+4 (app) can be developed in parallel.** Integration testing requires all three components.

---

## Future Enhancements (not in this plan)

- **Excel export** from results screen (Syncfusion dependency already in pubspec) — SUPERSEDED by addendum (now in-scope as CSV+PDF).
- **Drill presets** — save/load configurations to local storage — SUPERSEDED (now in-scope for v1 via Hive, see addendum §7.3).
- **Session history** — persist past drill results for review (stays v2, see TODOS.md).
- **Vibration threshold calibration** — per-target or global setting via app (stays v2, see TODOS.md).

---

## DESIGN REVIEW ADDENDUM (2026-04-20)

This addendum captures design decisions made during `/plan-design-review` on feature/system-v2. It supersedes any conflicting guidance in Tasks 3.7–4.6. Implementers should read this BEFORE touching the corresponding task.

### Ship Blockers (must fix before field test)

1. **App does not compile on feature/system-v2.** `lib/main.dart` imports `screens/device_discovery_screen.dart`, `lib/screens/results_screen.dart` imports `home_screen.dart`. Neither file exists on this branch. Task 3.7 and Task 4.2 were skipped during execution. The commit "feat: add all app screens" is misnamed — it added 4 of 6 screens. Must be resolved before any UI testing.

2. **STOP button has no confirmation guard.** Single tap ends a live drill. See §7.1 for fix.

3. **Target status uses color-only signaling.** ~8% of male trainers cannot distinguish the current red/green pair on TargetChip. For a safety-adjacent product, this is a real risk. See §6 for fix.

### DESIGN.md — Atriarch Range Console (v1)

**Aesthetic direction:** Dark-first "range console" — oscilloscope-meets-iPhone. Industrial but not mall-tactical. Near-black base, high-contrast status colors, big mono numerals. Readable in bright outdoor sun BECAUSE it's dark with high-luminance accents.

**Color tokens** (all screens, replace `Colors.blue`/`Colors.green`/etc. with semantic tokens):

```
  --bg-base:       #0A0D12   (near-black, not pure black)
  --bg-elevated:   #141820   (cards, sheets)
  --bg-card:       #1A1F2A
  --border:        #2A3140   (thin separators only)
  --text-primary:  #E8EDF5
  --text-secondary:#8892A8
  --text-tertiary: #4A5365

  --status-armed:     #F5A623   (amber, drill armed / timer running / in-progress-neutral)
  --status-live:      #39D98A   (bright green, active shoot target / success)
  --status-hit:       #5B9BFF   (blue, hit detected / neutral-positive)
  --status-violation: #FF3B4D   (saturated red, no-shoot hit / destructive)
  --status-late:      #FFB547   (orange, late hit / warning)
  --status-offline:   #4A5365   (grey, not online)
```

**Typography:**
- `--font-mono`: "JetBrains Mono", "IBM Plex Mono", ui-monospace — all numerals (timer, timing values, stats tables)
- `--font-sans`: "Inter Tight", "SF Pro Display" — all labels, headers, body copy
- Scale: 12 / 14 / 16 / 20 / 28 / 48 / 96pt (timer hero is 96)
- Weights: 300 (hero numerals), 500 (body), 700 (headers)
- **Not** the default Roboto. Bundle the fonts in `assets/fonts/`.

**Spacing scale:** 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64 (no ad-hoc values).

**Radius:**
- `--radius-sm`: 4 (inputs, chips)
- `--radius-md`: 8 (cards, buttons)
- `--radius-lg`: 12 (sheets, major containers)
- NO pill-shaped buttons. NO circles except the STOP button (deliberate physical "panic button" metaphor).

**Motion budget — 3 intentional motions total:**
1. Connection-status banner slide-in/out (300ms ease-out)
2. Drill "DRILL ACTIVE" label amber breathe-pulse (2s loop, opacity 0.7→1.0→0.7, subtle)
3. STOP ring-fill on press-hold (800ms linear — see §7.1)

**Outdoor readability rules:**
- Min text size: 14pt body, 18pt tappable labels
- Min contrast: 7:1 for primary text against `--bg-base` (AAA, sun demands it)
- Primary touch targets ≥ 44pt (HIG baseline, confirmed per user decision)
- Destructive touch targets (STOP) ≥ 120pt (already honored: 200pt drill STOP)

**Iconography:** Material Symbols rounded, locked allowlist:
`bluetooth`, `bluetooth_disabled`, `refresh`, `flash_on`, `gps_fixed`, `check_circle`, `warning`, `home`, `block` (no-shoot redundant marker), `gpp_good`, `gpp_bad`.

**Apply to Task 3.6 (main.dart):** Replace `primarySwatch: Colors.blue` + `useMaterial3: true` with a full `ThemeData.dark()` derived from the tokens above. Bundle JetBrains Mono + Inter Tight into `pubspec.yaml` assets.

---

### §1 Information Architecture

**Program Setup (Tasks 4.3, 4.4) restructure — one screen, numbered steps, preset row at top, sticky START.**

Replace current flat scroll with:

```
┌────────────────────────────────────────────────┐
│ ← Program A — Grouped Mode                     │
├────────────────────────────────────────────────┤
│ Preset: [ Standard ▾ ]    [ Save as… ]         │ ← preset dropdown, saved presets from Hive
├────────────────────────────────────────────────┤
│ STEP 1 — Assign Targets to Groups              │ ← hero section, largest
│ [ Group 1 (2 targets) · selected ]             │
│   T1  T11  [ + tap available ]                 │
│ [ Group 2 (1) ]  [ Group 3 (0) ]  [ 4 ]  [ 5 ] │
│                                                │
│ Available (online): T2  T12  T21  T22          │
│ Tap a group, then tap targets to assign.       │
├────────────────────────────────────────────────┤
│ STEP 2 — Timing                                │ ← collapsible, preset-filled
│ Start delay:          1.00 ↔ 3.00 s            │
│ Between activations:  0.50 ↔ 2.00 s            │
│ Required hits:        1    ↔ 3                 │
├────────────────────────────────────────────────┤
│ STEP 3 — Iterations per group:   [ 5 ]         │
├────────────────────────────────────────────────┤
│ (sticky, SafeArea bottom)                      │
│ [      START DRILL      ] amber, 56pt tall     │
└────────────────────────────────────────────────┘
```

**Home screen (Task 4.2) spec:**
- Persistent connection-status banner across top: `--status-live` when BLE connected, `--status-armed` when reconnecting, `--status-violation` when disconnected. Tap = go to Device Discovery.
- 3 tappable full-width rows: **Target Setup**, **Program A — Grouped**, **Program B — Individual**. Each has a one-line description beneath.
- No cards — just borders between rows. App UI rule: "cards only when card IS the interaction."

**Results (Task 4.6) headline:**
- Before the 6 stat cards, a single primary metric: `"12 / 15 completions · 0 violations"` in 28pt mono.
- Violation count dominates if > 0: use `--status-violation` for the whole headline.
- The 6 stat cards drop to 3 (completions / violations / duration) — remove redundant activations/hits/late cards. Those roll into the per-target table.

---

### §2 Interaction States

**Mid-drill connection loss (Task 4.5).** If `bleService.isConnected` flips false OR no event arrives for 30 seconds, show a dismissible banner at top of DrillRunningScreen:

```
  ┌──────────────────────────────────────────────┐
  │ ⚠ CONNECTION LOST — drill may still be running│
  │ [ Reconnect ]                    [ End Drill ]│
  └──────────────────────────────────────────────┘
```

- Timer keeps going (it's a phone stopwatch, BLE-independent).
- Reconnect: re-attempt BLE connection, re-subscribe to notifications, don't reset session.
- End Drill: flush to Results with whatever events arrived, mark session.incomplete = true.
- Implement `AppState.connectionLost` boolean + `DrillSession.incomplete` flag.

**Task 4.1 Target Discovery empty-state upgrade:**
```
  No targets found.
  Check:  · Transmitter powered and near you?
          · Targets powered on?
          · You connected to "{transmitter_name}" above?

  [ Scan for Targets ]     [ Change Transmitter ]
```

**Task 4.1 Partial discovery banner.** After `DDONE/`:
```
  Found 10 targets online.
  Expected more? Tap a target to flash its LED and verify.
```

**Task 4.6 Results "No session data" dead state:** add a `[ Return to Home ]` button below the message — currently there's no escape.

**Task 4.5 Drill stall detection:** If no event for 30s AND session has pending iterations, render a passive status chip above the timer: `"⚠ No activity for 30s"` in `--status-armed`. Does not block the drill; just surfaces the fact.

---

### §3 User Journey

**Identify-target UX (Tasks 4.1, firmware 2.3).**

**v1 (ship):** Tap-and-hold a TargetChip = CMD_IDENTIFY sent repeatedly while held (re-fire every 500ms since existing CMD_IDENTIFY flashes 3x over ~900ms). Release = stop. Trainer walks downrange with phone, presses the chip for the target they're looking at, sees matching flash. One round-trip per target identification — not four.

**v2 (deferred to TODOS.md):** Photo-based identification. Trainer takes one photo of the range, taps each target in the photo, app associates coordinates with target IDs. Future enhancement path.

**Between-student restart (Task 4.6 Results).** Replace single FAB with 3 explicit actions in a bottom action bar:
- `[ Run Again ]` — re-launches with the same `DrillConfig` (still in `AppState`). Re-uses group assignment and timing. One tap, new session.
- `[ New Drill ]` — same program (A or B), fresh config screen.
- `[ Home ]` — back to main menu.

Use `--bg-elevated` bar with 3 equal buttons. No FAB.

---

### §4 AI Slop Mitigations

- Remove `primarySwatch: Colors.blue`. Replace the Material 3 defaults entirely with `ThemeData.dark()` derived from the §DESIGN.md tokens above.
- Remove `Card` wrappers from non-interactive content. Specifically: `_StatCard` in Task 4.6 becomes a simple Column with border-top/border-bottom — no Card.
- Replace all named `Colors.X` literals in Tasks 3.7–4.6 with semantic tokens (ex: `Theme.of(context).extension<AtriarchTokens>()?.statusLive`).
- Bundle Inter Tight + JetBrains Mono fonts. Not Roboto. Not Inter (default). Not the Material default stack.

---

### §5 Design System (covered in DESIGN.md section above)

Create `DESIGN.md` at repo root containing the tokens, typography, spacing, motion, and iconography rules specified above. Every implementer references it before building a screen.

Implement tokens in Flutter via a `ThemeExtension<AtriarchTokens>` class in `lib/theme/atriarch_theme.dart`.

---

### §6 Responsive & Accessibility

**Colorblind-safe TargetChip (Tasks 4.1, widgets/target_chip.dart).** Color is double-encoded with iconography:
- Offline: grey chip + `bluetooth_disabled` leading icon (14pt).
- Available (unassigned): `--bg-card` chip + plain "T{id}" text, no icon.
- Grouped: group-color chip + group number as trailing badge (e.g. "T5 ᴳ²").
- No-shoot: violation-red chip + `block` leading icon. ALWAYS shows icon — color alone is not enough.

Update the `TargetChip` widget signature to accept `groupColor` (nullable, from the 5-group palette in §7.2 below).

**Touch target sizes (project-wide rule in DESIGN.md):**
- Minimum 44pt for all tappable elements (Apple HIG baseline).
- IncDec buttons grow from ~30pt → 44pt (padding 16 + 20pt icon = 52pt effective).
- TargetChip minimum 44pt height.
- All FABs and IconButtons: 44pt minimum.

**Semantics:**
- Every IconButton gets a `tooltip` and a `Semantics(label: ...)`.
- STOP button announces: `"STOP. Press and hold to end the drill."` — makes the press-hold pattern discoverable to screen readers.

**Reduce Motion:** respect `MediaQuery.of(context).disableAnimations`. Under reduce-motion, the STOP ring-fill becomes an instant single-tap (trade: we lose the accidental-tap guard — acceptable because the user has opted into motion reduction and likely has different accessibility needs).

**Typography min contrast:** 7:1 against `--bg-base`. Audit `--text-tertiary: #4A5365` — it's borderline against `--bg-base: #0A0D12`; reserve it for non-essential labels only (timestamps, secondary metadata).

---

### §7 Resolved Design Decisions

**§7.1 STOP safety — press-and-hold with 800ms ring-fill.**

Drill STOP button (Task 4.5):
- Single tap: no-op (no visual feedback — dead press).
- Press-and-hold: a ring around the 200pt circle fills clockwise over 800ms. Fill is `--status-violation`. If released before completion, ring snaps back to empty.
- At 800ms complete: fires `stopDrill()`.
- Under Reduce Motion: single tap fires immediately (accessibility override).

Implementation: wrap ElevatedButton in a `GestureDetector` with `onLongPressStart` / `onLongPressEnd`, drive an `AnimationController` (duration: 800ms).

Semantics: `label: "STOP button. Press and hold to end the drill."`

**§7.2 Drill preview — group-color confirmation (requires firmware extension).**

Add a `[ Preview Groups ]` button above `[ START DRILL ]` on Program Setup. Tapping it sends a new command to the transmitter, which broadcasts to all targets simultaneously:

- Each target in Group 1 lights up **magenta** (steady).
- Each target in Group 2 lights up **cyan** (steady).
- Each target in Group 3 lights up **yellow** (steady).
- Each target in Group 4 lights up **purple** (steady).
- Each target in Group 5 lights up **lime** (steady).
- No-shoot targets within any group: **blink** in that group's color (on/off at 2 Hz).
- After 5 seconds, all targets go dark automatically.

This visually confirms grouping + no-shoot assignments simultaneously, without previewing the randomized activation sequence (which trainers don't want to spoil).

**Firmware scope additions (Tasks 1.x + 2.x):**
- Target firmware (Task 1.2 + new helper): new `CMD_PREVIEW` with payload `{CMD_PREVIEW, color_index, blink_flag}` where `color_index` ∈ {1..5} maps to the 5 group colors, `blink_flag` ∈ {0, 1}. Enters STATE_PREVIEW for 5000ms then returns to IDLE.
- Target firmware: extend LED helpers with `setLedGroupColor(int colorIndex, bool blink)`. Color indices map to CRGB constants.
- Transmitter firmware (Task 2.4 extension): parse new BLE command `PREVIEW/<g1>/<g2>/<g3>/<g4>/<g5>/<ns>/`. For each group, send `{CMD_PREVIEW, groupIndex, 0}` to every target in that group. For each no-shoot target, send `{CMD_PREVIEW, groupIndex, 1}` (overrides).
- App (Task 4.4 Program A + 4.3 Program B): wire `[ Preview Groups ]` button → `TransmitterProtocol.encodePreview(groups, noShootIds)`.

Color palette on WS2812 (tested against green cardboard at noon — provisional, may need calibration):
```
  Group 1 magenta: CRGB(255, 0, 120)
  Group 2 cyan:    CRGB(0, 200, 255)
  Group 3 yellow:  CRGB(255, 200, 0)
  Group 4 purple:  CRGB(140, 0, 255)
  Group 5 lime:    CRGB(140, 255, 0)
```

**§7.3 Drill presets — v1 ships with Hive-backed user presets.**

- Add `hive` + `hive_flutter` to `pubspec.yaml` (if not already). Already listed as implementation option in TODOS.md.
- Create `lib/models/drill_preset.dart` — stores `DrillConfig` + a name string.
- Create `lib/services/preset_service.dart` — CRUD on a Hive box `presets`.
- Program Setup screens get: `Preset: [dropdown with saved + "Custom"]  [Save as…]  [Manage…]`.
  - Dropdown shows user-named presets, plus 3 built-in starters ("Easy", "Standard", "Hard") that new users see on first launch.
  - "Save as…" prompts for a name, saves current config under that name.
  - "Manage…" opens a bottom-sheet list of presets with rename/delete actions.
- Built-in presets are seeded on first Hive-open but are editable (and deletable) like user presets.

**§7.4 Home connection-status banner** — see §1 Home screen spec.

**§7.5 Sticky START on Program Setup** — see §1 Program Setup restructure. `START DRILL` wrapped in a `SafeArea` + `BottomAppBar` below the scroll region.

**§7.6 Drill stall detection threshold — 30 seconds** of event silence during a running drill triggers the passive stall chip (§2). Tuning note: if field test shows false positives for longer delayMax values, raise to `max(30, delayMax * 2 + 10)`.

**§7.7 Results export — CSV + PDF both.**

Task 4.6 gets a share action in the AppBar (`Icons.ios_share`). Tapping opens a bottom sheet:
- `[ Export CSV ]` → writes a CSV with one row per `SessionEvent` (timestamp, type, targetId, hitNumber, totalTimeMs) using `syncfusion_flutter_xlsio` (already in plan). Trigger iOS share sheet.
- `[ Generate PDF ]` → renders a one-page summary (headline stat + per-target table + event log) using `pdf` + `printing` packages. Trigger iOS share sheet.

Field names on CSV export match the `SessionEvent` model exactly — no transformation — so it round-trips into analytics tools.

---

### §8 NOT in Scope (explicitly deferred)

| Item | Why deferred | Captured in |
|---|---|---|
| Photo-based identify with tap-to-assign | v2+; requires AR coordinate capture, UI exploration, validation | TODOS.md "v2 app" |
| Student-facing large timer display | v2 (user memory confirms) | TODOS.md |
| Voice commands (start/reset) | v2 (noise environment will be brutal) | TODOS.md |
| AI drill generation | v2 | TODOS.md |
| Cross-session drill history | v2 (current: single-session only) | TODOS.md |
| Android build | v2 (v1 = iPhone only per CEO) | TODOS.md |
| Per-target threshold tuning UI | v2, requires firmware CONFIG/ command | TODOS.md |
| Advanced export (IPSC/Practiscore) | v2 | TODOS.md |
| Dark/light theme toggle | v1 ships dark-only; light theme is v2 or never | — |
| Tablet-specific layouts | v1 is phone-sized; tablet uses scaled phone UI | — |

---

### §9 What Already Exists (reuse, don't rebuild)

- `TargetChip` widget (lib/widgets/target_chip.dart) — extend with group-color prop + icons per §6, don't rewrite.
- `IncDec` widget (lib/widgets/IncDec.dart, rename to inc_dec.dart per Task 3.7) — bump touch targets to 44pt per §6.
- `DrillTimer` widget — already monospace-styled, bump to JetBrains Mono per §DESIGN.md, keep the rest.
- `SessionEvent` model + event-tile rendering in `ResultsScreen` — keep structure, restyle per §DESIGN.md.
- BLE service + protocol encoding — no design changes needed.

---

### §10 Revised Task Order (impacts execution)

Given the addendum, suggest re-ordering execution:

1. **First: compile-unblock the app** — implement Task 3.7 (DeviceDiscoveryScreen), Task 4.2 placeholder (HomeScreen), wire Task 4.1 (TargetDiscoveryScreen). `flutter analyze` must pass before any more UI work.
2. **Second: create DESIGN.md + theme** — `lib/theme/atriarch_theme.dart`, bundle fonts, ThemeExtension. Gate all subsequent UI PRs on using tokens.
3. **Third: firmware extension for §7.2 Preview** — Tasks 1.2/1.3/2.4 get CMD_PREVIEW + BLE PREVIEW/ command BEFORE app previews it. Otherwise app wiring stalls.
4. **Then: app screens in plan order** (Tasks 4.1 → 4.6), applying addendum specs.
5. **Last: export (§7.7) + presets (§7.3)** — additive, don't block field test.

---

*End of Design Review Addendum — 2026-04-20*

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | CLEAR | mode: SCOPE_EXPANSION, 0 critical gaps, 7 proposals all accepted |
| Codex Review | `/codex review` | Independent 2nd opinion | 2 | issues_found | codex flagged plan-level issues on 2 runs |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (PLAN) | 21 issues, 1 critical gap, FULL_REVIEW mode |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | issues_open (FULL) | score: 3/10 → 8/10, 14 decisions made, 2 unresolved (see below) |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

**UNRESOLVED:** 2 items
- Identify-target implementation path for v1: is "tap-and-hold repeats CMD_IDENTIFY" acceptable as interim, or do we fast-track photo-based? (Recommend v1 = tap-and-hold; photo-based = v2.)
- Group-color preview (§7.2) requires a firmware protocol extension that wasn't in the original plan. Needs eng-review re-confirmation that CMD_PREVIEW + BLE PREVIEW/ command fit within the ATmega328P's RF24 payload budget and serial parser.

**VERDICT:** CEO + ENG + DESIGN ALIGNED — ready to implement WITH addendum applied. Recommend re-running `/plan-eng-review` (or `/codex review`) on §7.2 firmware extension before that task lands. 1 ship blocker (compile failure on feature/system-v2) must resolve in Task 3.7 + 4.2 execution first.
