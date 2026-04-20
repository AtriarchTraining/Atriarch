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

Note (2026-04-20): This plan was written 2026-03-31 before the CEO review and eng review
landed. Several items below were subsequently pulled into v1 scope by the CEO review
(drill presets, session history, JSON event log). Consult the CEO design doc at
`~/.gstack/projects/AtriarchTraining-Atriarch/jeremygill-feature-system-v2-design-20260419-133046.md`
and the eng plan at `~/.gstack/projects/AtriarchTraining-Atriarch/eng-plans/2026-04-20-atriarch-v2-engineering-plan.md`
for authoritative scope. See the Design Review Addendum below for UI specifics.

- **Excel export** from results screen (Syncfusion dependency already in pubspec)
- **Drill presets** — save/load configurations to local storage
- **Session history** — persist past drill results for review
- **Vibration threshold calibration** — per-target or global setting via app

---

## DESIGN REVIEW ADDENDUM v2 (2026-04-20)

This supersedes the earlier v1 addendum (removed). v1 was written without reading the
CEO-approved design doc or the eng plan — it reached a light/dark conflict and missed
seven CEO-approved v1 expansions. This version reconciles against:

- **CEO doc:** `~/.gstack/projects/AtriarchTraining-Atriarch/jeremygill-feature-system-v2-design-20260419-133046.md` (2026-04-19)
- **Eng plan:** `~/.gstack/projects/AtriarchTraining-Atriarch/eng-plans/2026-04-20-atriarch-v2-engineering-plan.md` (2026-04-20)
- **This task plan:** `docs/superpowers/plans/2026-03-31-atriarch-implementation.md` (2026-03-31)

Both CEO and eng docs are authoritative. When this addendum conflicts with a Task in
Phase 3 or 4 above, this addendum wins. When this addendum would conflict with the
CEO/eng docs, the CEO/eng docs win.

### §0 Ship Blockers (resolved 2026-04-20)

- [x] App compile blocker — `lib/screens/device_discovery_screen.dart` and
      `lib/screens/home_screen.dart` existed as imports but not files. Built per
      Tasks 3.7 / 4.2. `flutter analyze` passes. (commit `808fa1c`)
- [x] `IncDec.dart` → `inc_dec.dart` rename (Task 3.7 Step 5). (commit `808fa1c`)

Open blockers flowing out of this review:
- [ ] STOP button has no confirmation guard (§7.1 — press-and-hold)
- [ ] TargetChip uses color-only signaling; colorblind trainers misread no-shoot (§6.1 — redundant icons)
- [ ] `primarySwatch: Colors.blue` with no theme tokens → violates CEO MUST-tier outdoor-readability (§1 DESIGN.md + §7.2 auto-theme)

---

### §1 DESIGN.md — Atriarch Range Console (dual-theme, v1)

Create `DESIGN.md` at repo root. Implement tokens in `lib/theme/atriarch_theme.dart`
via `ThemeExtension<AtriarchTokens>`. Both light and dark themes ship; runtime
auto-toggle per §7.2.

**Aesthetic direction:** Industrial instrument. Readable outdoors in direct sun by
flipping to light-with-max-brightness. Readable indoors/dusk in dark mode. Every
status is double-encoded (color + icon + label position) for colorblind trainers and
sun-washed glass.

**LIGHT theme tokens** (outdoor / high-ambient, primary per CEO doc):
```
  --l-bg-base:        #FFFFFF
  --l-bg-elevated:    #F2F5FA
  --l-bg-card:        #E8EDF5
  --l-border:         #C3CBD9
  --l-text-primary:   #0A0D12    (7:1+ contrast vs bg)
  --l-text-secondary: #3A4355
  --l-text-tertiary:  #6A7388

  --l-status-armed:     #B76E00  (amber — armed / running)
  --l-status-live:      #0E7A3E  (green — active shoot target)
  --l-status-hit:       #1E4FC7  (blue — hit detected)
  --l-status-violation: #B3001F  (deep red — no-shoot hit)
  --l-status-late:      #B36F00  (warm orange — late hit)
  --l-status-offline:   #6A7388
  --l-status-unreachable:#B3001F (same visual weight as violation — it matters)
```

**DARK theme tokens** (indoor / low-ambient):
```
  --d-bg-base:        #0A0D12
  --d-bg-elevated:    #141820
  --d-bg-card:        #1A1F2A
  --d-border:         #2A3140
  --d-text-primary:   #E8EDF5
  --d-text-secondary: #8892A8
  --d-text-tertiary:  #4A5365

  --d-status-armed:     #F5A623
  --d-status-live:      #39D98A
  --d-status-hit:       #5B9BFF
  --d-status-violation: #FF3B4D
  --d-status-late:      #FFB547
  --d-status-offline:   #4A5365
  --d-status-unreachable:#FF3B4D
```

**Contrast audit:** every token pair tested at 7:1 minimum for body text, 4.5:1 for large text. Light theme at max phone brightness is the field-test sun use case.

**Typography (same across themes):**
- `--font-mono`: JetBrains Mono — all numerals (timer, timing values, stats tables, event log timestamps)
- `--font-sans`: Inter Tight — labels, headers, body copy
- Scale: 12 / 14 / 16 / 20 / 28 / 48 / 96pt
- Weights: 300 (hero numerals), 500 (body), 700 (headers)
- Bundle fonts in `assets/fonts/`. `pubspec.yaml` declares.
- **Not** Roboto. **Not** Inter (the generic one). **Not** the Material default.

**Spacing scale:** 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64. No ad-hoc values.

**Radius:** `--radius-sm` 4 (inputs, chips), `--radius-md` 8 (cards, buttons), `--radius-lg` 12 (sheets). No pill buttons. Circle only for the STOP panic button (200pt).

**Motion budget — 4 intentional motions:**
1. Connection banner slide-in/out (300ms ease-out)
2. "DRILL ACTIVE" amber breathe-pulse (2s loop, opacity 0.75→1.0→0.75)
3. STOP ring-fill on press-hold (800ms linear — §7.1)
4. Theme cross-fade on auto-toggle (400ms)

Under `MediaQuery.disableAnimations`: breathe stops; STOP becomes single-tap; cross-fade is instant.

**Outdoor readability rules:**
- Min text: 14pt body, 18pt tappable labels
- Min touch target: 44pt (HIG). STOP = 200pt. Primary START = 56pt.
- Min contrast: 7:1 body text against bg-base
- When auto-theme flips to light: also `ScreenBrightness.setScreenBrightness(1.0)`; restore prior brightness when flipping back or leaving drill context.

**Iconography allowlist** (Material Symbols rounded): `bluetooth`, `bluetooth_disabled`, `refresh`, `flash_on`, `gps_fixed`, `check_circle`, `warning`, `home`, `block`, `gpp_good`, `gpp_bad`, `ios_share`, `volume_up`, `photo_camera`, `groups`, `person`, `play_arrow`, `chevron_right`, `more_vert`, `edit`, `delete`. Implementer does not add new icons without DESIGN.md update.

---

### §2 Information Architecture

**Home screen** (already built; needs token migration):
- Connection banner (top, persistent) — add `reconnecting` amber state per eng §1.10
- 3 rows: Target Setup / Program A — Grouped / Program B — Individual
- 4th row conditionally: "Recent Drills" (§4.E) — shown only when `SessionRepository.currentSession` has ≥1 completed drill

**Program Setup (A & B)** — single screen, preset row, numbered steps, sticky START:

```
┌────────────────────────────────────────────────┐
│ ← Program A — Grouped Mode                     │
├────────────────────────────────────────────────┤
│ Preset: [ Bill Drill ▾ ]      [ Save… ] [ ⋯ ] │
├────────────────────────────────────────────────┤
│ STEP 1 — Assign Targets to Groups              │
│   (group cards, tap-to-select, tap-target-to-  │
│    assign; each chip shows name or T#)         │
│                                                │
│   [ Preview Groups ] ← lights groups w/ colors │
├────────────────────────────────────────────────┤
│ STEP 2 — Timing                                │
│   Start delay:         1.00 ↔ 3.00 s           │
│   Between activations: 0.50 ↔ 2.00 s           │
│   Required hits:       1    ↔ 3                │
├────────────────────────────────────────────────┤
│ STEP 3 — Iterations per group:    5            │
├────────────────────────────────────────────────┤
│ (sticky BottomAppBar, SafeArea)                │
│ [        START DRILL        ]  56pt tall        │
└────────────────────────────────────────────────┘
```

- Step headers: 14pt uppercase label `--text-tertiary`, 20pt section title `--text-primary` 700
- Preset dropdown resolves to a `DrillPreset` from `PreferencesRepository`. Editing values after selecting a preset shows "— modified" suffix; "Save…" overwrites or saves-as
- `[ ⋯ ]` menu: Rename preset / Delete preset / Set as default / Duplicate

**Results** — headline + 3 cards + per-target table + action bar:

```
┌────────────────────────────────────────────────┐
│ ← Drill Results                          [ 🔗 ]│
├────────────────────────────────────────────────┤
│ 12 of 15 completions   ·   0 violations        │  headline 28pt mono
│ 4m 12s · Bill Drill                            │
├────────────────────────────────────────────────┤
│   [Completions 12] [Violations 0] [Late 1]     │
├────────────────────────────────────────────────┤
│ Per-Target Breakdown                           │
│ Target  | Hits | Done | Avg ms | NS | Late    │
│ Flipper | 3    | 1    | 812    | 0  | 0       │
│ Steel L | 2    | 1    | 945    | 0  | 1       │
├────────────────────────────────────────────────┤
│ ▸ Event Log  (collapsed by default)            │
├────────────────────────────────────────────────┤
│ ┌─── sticky bottom action bar ───┐             │
│ │ [Run Again] [New Drill] [Home] │             │
│ └────────────────────────────────┘             │
└────────────────────────────────────────────────┘
```

- Violation headline turns `--status-violation` when > 0
- Per-target rows use target NAME if renamed; fall back to T{id}
- Event Log = collapsible expansion tile

---

### §3 Interaction States

**Target states** (chip visuals; all double-encoded):

| State | Background | Icon | Label example |
|-------|-----------|------|---------------|
| Online, unassigned | `--bg-card` | none | `Flipper` (or `T3`) |
| Online, in group G2 | group-color tinted | group-number badge ᴳ² | `Flipper ᴳ²` |
| Online, no-shoot | red-tinted | `block` leading | `Flipper · NO-SHOOT` |
| No-shoot in group | red-tinted + group badge | `block` + ᴳ² | `Flipper · NO-SHOOT ᴳ²` |
| Unreachable (≥3 missed heartbeats) | amber-tinted | `warning` | `Flipper · UNREACHABLE` |
| Offline | grey | `bluetooth_disabled` | `T7 · OFFLINE` |

**Drill-running connection loss** (aligns with eng §1.2 + §1.10):
- BLE `ConnectionStatus.reconnecting` → top banner "CONNECTION LOST · reconnecting…" in `--status-armed`. Timer continues. Banner auto-dismisses on reconnect.
- Reconnect successful → app sends `SNAP/` → transmitter returns `SNAP_REPLY/…` → app reconciles session state.
- `ConnectionStatus.failed` (30s+ down) → banner shifts to `--status-violation`: "CONNECTION LOST · could not reconnect" + `[ Retry ]` `[ End Drill ]`. End Drill flushes to Results with `session.incomplete = true`.

**UI state sync** (aligns with eng §1.3 ACK requirement):
- **START button:** after tap, enters "ARMING…" state (disabled + amber spinner). Unblocks only after first `ACT/<id>/` arrives (round-trip confirmed). >3s with no ACT → error: "No response from transmitter. Check connection." Button re-enables.
- **STOP button:** after press-hold completes, enters "STOPPING…" state (ring gone, spinner + "STOPPING…" label). Unblocks and navigates to Results only after `STOP_ACK/` or 5s timeout. Timeout path shows warning but still navigates.

**Empty state** (Target Setup, no discoveries):
```
  No targets found.
  Check:  · Transmitter powered and near you?
          · Targets powered on?
          · Connected to "[device name]"?

  [ Scan for Targets ]        [ Change Transmitter ]
```

**Partial discovery banner** (after `DDONE/`):
```
  Found 10 targets online.
  Expected more? Long-press a target to identify it,
  or tap "Walk-the-Range" to flash the fleet in sequence.
```

---

### §4 CEO-approved SHOULD-tier UI specs

**§4.A Auto-theme** — addressed in §7.2.

**§4.B User-named targets.** Long-press a TargetChip opens a bottom sheet:
```
  🔦 Identify (flash LED)
  ✎  Rename
  🚫 Toggle No-Shoot  (currently OFF)
  🗑  Remove from fleet
```
- Rename: TextField dialog, 20-char max, empty reverts to `T{id}`. Saves to `PreferencesRepository.targetNames`.
- Name used everywhere a target is referenced (chip, per-target table, event log, drill preview, results, log JSON).
- Remove = soft-delete. Hidden from UI until "Show removed" toggle in AppBar reveals them. Prevents accidental loss.

**§4.C Ready-audio chime.**
- Trigger: fleet all-online after a discovery cycle (fires once per cycle, not per `D/<addr>/`).
- Sound: 2-note ascending bell, ~500ms, `assets/sounds/ready.mp3`, bundled via `just_audio`.
- Respects iOS silent mode (don't override for non-alerting audio).
- `Settings > Ready Audio` toggle + volume slider. Default ON, volume 0.7. Persisted in `PreferencesRepository.appSettings`.

**§4.D Shareable drill result image.** Rendered via `screenshot` package against a decoupled widget tree (not live Results):
```
  ┌────────────────────────────────────────┐
  │  ATRIARCH                              │  wordmark
  │  Bill Drill · 4m 12s                   │
  │  2026-04-20                            │
  │                                        │
  │       12 of 15                         │  headline
  │      completions                       │
  │                                        │
  │  · 0 violations · 1 late hit ·         │
  │                                        │
  │  Per-target:                           │
  │   Flipper    812ms avg · 3 hits        │
  │   Steel L    945ms avg · 2 hits        │
  └────────────────────────────────────────┘
```
- Always dark theme (brand consistency regardless of active app theme).
- 1080×1920 (iPhone wallpaper / IG story aspect).
- Entry via Results AppBar share icon → bottom sheet (§4.D+F).

**§4.E Session history** (current-session only, CEO-locked):
- Home shows "Recent Drills" row when `SessionRepository.currentSession` has ≥1 completed drill. Count badge (`3 drills this session`).
- Tap opens `RecentDrillsScreen` — most-recent-first list. Each row: preset name, start time, 3-line summary.
- Tap a row → Results in read-only mode (share + back only; no Run Again from history since config may have diverged).
- Auto-cleared on background-to-foreground when `sessionStart` is >8h old (class day ended).

**§4.F Per-drill JSON event log.** Versioned. Exportable via share sheet.
```json
{
  "version": 1,
  "drillId": "...",
  "startedAt": "2026-04-20T14:05:00Z",
  "preset": { "name": "...", "config": { ... } },
  "targetNames": { "1": "Flipper", ... },
  "events": [ { "t": "...", "type": "HIT", "targetId": 1, ... } ]
}
```
Stored in `DrillLogRepository` Hive box `drill_logs`.

**§4.D+F combined share sheet** (Results AppBar `ios_share`):
```
  Share drill

  🖼  Share result image        (for student)
  📄 Export drill log (JSON)   (for Jeremy)

                                  [ Cancel ]
```

---

### §5 On-range target-identity mapping (codex CORE problem)

v1 ships BOTH tap-and-hold AND photo-based per user decision 2026-04-20.

**§5.A Tap-and-hold identify** (spot-check fallback):
- Press-hold a TargetChip ≥200ms → app sends repeated `IDENT/<addr>/` at 700ms intervals while held. Release = stops.
- Target's white 3-flash re-fires each command → near-continuous flash while held.
- Haptic: light impact on press + on release.
- First-use tooltip: "Hold to flash. Release to stop."

**§5.B Walk-the-Range identify** (sequential flash for mental mapping):
- Target Setup AppBar action `[ Walk-the-Range ]`.
- Tap → sends IDENT to targets in decimal-ID order, 3s between each. Total ≈ `N × 3s`.
- If ready-audio enabled: TTS announces each target's name (or ID) simultaneously (`flutter_tts`). Silent mode disables TTS.
- Can cancel mid-sequence (button becomes `[ Cancel ]` during walk).

**§5.C Photo-based fleet mapping** (primary persistent spatial mapping):
- New screen `lib/screens/fleet_map_screen.dart` from Target Setup AppBar action `[ Photo Map ]`.
- Flow:
  1. Trainer sets phone on tripod/steady surface, faces range, taps `[ Take Photo ]`.
  2. Camera permission flow (first use).
  3. Photo captured (`camera` package; resize to 2048px longest edge; JPEG q85).
  4. Photo displayed. Tap `[ Start Mapping ]`.
  5. App auto-runs Walk-the-Range at 4s cadence. At each flash, trainer taps the target's position in the photo. Tap = circular region (48pt radius default, resizable via long-press).
  6. On completion: photo file path + regions saved to `PreferencesRepository.fleetMap`. Photo lives in app docs dir.
- Map mode use: Target Setup has `[Chips ◯◉ Map]` AppBar toggle. Map mode shows photo + region overlays. Tap region = tap chip (assign to selected group). Long-press region = §4.B bottom sheet.
- Unreachable/Offline states surface on regions with the same iconography as chips.
- `[ Retake Photo ]` AppBar action re-runs capture. Prior maps preserved in `PreferencesRepository.fleetMapHistory` (last 3) for accident recovery.
- Scope warning: ~1 week of human work; CC ~2h. Camera permissions, iOS photo storage, region UX, persistence complexity are real. `/plan-eng-review` should sign off on camera package choice and iOS file storage patterns (see §11).

**Rationale for shipping both:** tap-and-hold is 15 min of work with independent value (spot-check during class). Photo-map is the primary setup workflow. If photo-map has problems in field, tap-and-hold + Walk-the-Range remain a complete fallback.

---

### §6 Responsive & Accessibility

**§6.1 Colorblind-safe TargetChip** — redundant icons + labels per §3. Run Sim Daltonism (deuteranope + protanope) before field test. If group-color palette (magenta/cyan/yellow/purple/lime) has confusable pairs under CVD, adjust palette.

**§6.2 Touch targets** — 44pt minimum. STOP = 200pt. Primary action = 56pt.

**§6.3 Semantics** — every IconButton has tooltip + `Semantics(label:)`. STOP: `label: "Stop button. Press and hold for 800 milliseconds to end the drill."` Group-color preview announces each group via `SemanticsService.announce`.

**§6.4 Reduce Motion** — `MediaQuery.disableAnimations` disables breathe-pulse, makes STOP single-tap, makes theme cross-fade instant, makes banner instant.

**§6.5 Dynamic Type** — respect `textScaleFactor` up to 1.3; clamp above that (timer clips otherwise).

**§6.6 VoiceOver** — test pass for primary flows. Drill event announcements are opt-in (Settings toggle) — a chatty VoiceOver during live fire is a distraction.

---

### §7 Resolved Design Decisions

**§7.1 STOP press-and-hold (800ms ring-fill).**
- Single tap: no-op.
- Press-hold: ring around 200pt button fills clockwise over 800ms in `--status-violation`. Early release = snap back.
- At 800ms complete: `AppState.stopDrill()` → UI enters STOPPING per §3.
- Reduce Motion: single tap fires immediately.
- Impl: `GestureDetector` + `AnimationController(duration: 800ms)`.

**§7.2 Dual-theme auto-toggle.**
- `light_sensor` package reads ambient lux on iOS.
- Dark → Light: lux > 1000 for ≥2s continuously → switch, set brightness 1.0.
- Light → Dark: lux < 200 for ≥2s continuously → switch, restore prior brightness.
- Otherwise hold. Hysteresis prevents flicker.
- Theme persisted in `app_settings.themeMode`. On launch, restore last theme while sensor warms up.
- Manual override: `Settings > Theme > [Auto | Light | Dark]`. Auto is default. Manual persists until user picks Auto again.
- `light_sensor` failure fallback: Auto-light 6am–6pm local, Auto-dark otherwise. "Ambient sensor unavailable" toast shown once.
- Brightness override applies only in app foreground during drill/setup context; reverts on backgrounding or Home.

**§7.3 Group-color preview (firmware extension).**
- New firmware command `CMD_PREVIEW{color_index, blink_flag}`, new BLE command `PREVIEW/<g1>/<g2>/<g3>/<g4>/<g5>/<ns>/`.
- Group palette: G1 magenta · G2 cyan · G3 yellow · G4 purple · G5 lime.
- No-shoot within a group: blink in group color (2 Hz).
- 5-second preview then auto-off.
- **Gated on `/plan-eng-review`** airtime + serial parser confirmation (§11).

**§7.4 Home connection banner** — already built; needs token migration + amber `reconnecting` state.

**§7.5 Sticky START** — BottomAppBar + SafeArea, floats above keyboard on focused input.

**§7.6 Drill stall — heartbeat-driven (replaces prior 30s generic threshold).**
- Target missing ≥3 heartbeats (4.5s window) → inline UNREACHABLE chip on Drill Running screen.
- ACK retry (eng §1.3) is the primary signal; heartbeat chip is secondary visibility.
- All live targets Unreachable → fullscreen banner with `[ End Drill ]`.

**§7.7 Results export — image + JSON.**
- Image for students (§4.D). JSON for Jeremy debug (§4.F). Combined sheet §4.D+F.
- CSV NOT in v1 (JSON covers the need).

**§7.8 Reset vs Restart.**
- **During drill:** STOP IS reset. Safe abort. No save to session history, no Results. Returns to Program Setup with config loaded.
- Mid-drill Restart deliberately NOT available — re-arming targets while shooter is downrange is unsafe.
- **Post-drill (Results):** `[ Run Again ]` (same config, new session) + `[ New Drill ]` (same program, config editable) + `[ Home ]`.
- Incomplete drills (BLE drop) save to history tagged as incomplete.

**§7.9 No-shoot policy = log + continue (option 1).**
- CEO-doc working default, confirmed.
- Violations counted in headline, logged to drill log.
- Optional violation-audio-cue (Settings toggle, off default): distinct short buzz on `EVT_NOSHOOT_HIT` during drill. Trainer awareness without stopping.
- v2 open: per-preset policy.

**§7.10 First-run onboarding wizard — 4 steps.**
`lib/screens/onboarding/`:
1. `welcome_step.dart` — one-sentence what-Atriarch-is + Continue.
2. `pair_transmitter_step.dart` — runs device discovery. Success = transmitter UUID persisted. Failure = help text + retry.
3. `discover_targets_step.dart` — runs target discovery. `[ Walk-the-Range ]` + optional `[ Photo Map ]`. Skip allowed with warning.
4. `first_drill_step.dart` — pre-filled Program B, 2 targets, conservative timing. Start → real drill → Results with onboarding-complete banner + `[ Finish Onboarding ]`.
- Progress bar top: `●●○○` / etc.
- Completion flips `app_settings.onboardingComplete = true`.
- Re-runnable via `Settings > Run Onboarding` (for demos / recovery).

**§7.11 Setup-time target — under 15 min for 8 targets.**
- All persistence (presets, fleet map, target names) carries session-to-session.
- Onboarding is one-time; cold-start to Home is ~5s afterwards.
- `SessionRepository.lastSetupTime` recorded; debug overlay (long-press version in Settings) exposes it for self-audit.

---

### §8 NOT in Scope (explicit deferrals)

| Item | Why | Landing |
|---|---|---|
| Cross-day drill history | Eng locked current-session only | TODOS.md |
| Android build | iPhone-only v1 | TODOS.md |
| Second transmitter / hot spare | Single-TX reality | TODOS.md |
| Cloud sync / multi-range | Pre-product-validation | TODOS.md |
| Voice commands / gestures | Post-field-test UX | TODOS.md |
| AI drill generation | v2 differentiator | TODOS.md |
| Student companion app | Multi-user v2 | TODOS.md |
| Practiscore / IPSC | v2 ecosystem | TODOS.md |
| Per-target threshold UI | Compile-time OK for v1 | TODOS.md |
| ISR sensor polling | Free with v2 accelerometer | TODOS.md |
| Target self-report / pairing journal | Stable v1 fleet | TODOS.md |
| CSV export | JSON + image cover v1 | — |
| Dark-theme-forced-primary | CEO: light is primary outdoor | — |

---

### §9 What Already Exists (reuse)

- `TargetChip` — extend with group-color + icons + rename support (§3, §4.B). Don't rewrite.
- `inc_dec.dart` — bump touch targets to 44pt, migrate to tokens.
- `DrillTimer` — keep mono styling, swap to JetBrains Mono via theme.
- `DeviceDiscoveryScreen`, `HomeScreen` (commit 808fa1c) — restyle with tokens.
- `AppState`, `BleService`, `TransmitterProtocol` — extend per eng §1.10 + repository split §1.1.
- `SessionEvent` — extend with ACK / HB / SNAP types per eng §1.3.
- `drill_config.dart` — add `version: 1` + Hive adapter.

---

### §10 Revised Execution Order (overlays eng §1.16 Gate 1)

**Gate 1 (compileable + safe single drill — field-test blocker):**
1. [x] Compile blocker resolved (commit 808fa1c)
2. [ ] Fix `EVT_PONG` responder-ID bug (`transmitter.ino:173`, eng §1.16)
3. [ ] Remove `delay(200)` in `target.ino:177` (eng §1.14)
4. [ ] `DESIGN.md` + `lib/theme/atriarch_theme.dart` with LIGHT theme only (skip auto-toggle until Gate 2)
5. [ ] STOP press-and-hold (§7.1) on Drill Running
6. [ ] TargetChip colorblind-safe icons (§3, §6.1)
7. [ ] UI state sync: START→ACT ACK, STOP→STOP_ACK (§3 + eng §1.3)
8. [ ] ACK + heartbeat firmware (eng §1.3, §1.5)
9. [ ] BLE safe-stop in target (eng §1.2); SNAP/SNAP_REPLY in transmitter
10. [ ] One drill end-to-end; STOP safe in every state

**Gate 2 (CEO SHOULD-tier expansions):**
11. [ ] Hive + repositories (eng §1.1)
12. [ ] Dark theme + auto-toggle (§7.2)
13. [ ] User-named targets (§4.B)
14. [ ] Drill presets + preset row on Program Setup (§2)
15. [ ] Ready-audio chime (§4.C)
16. [ ] Session history + Recent Drills row (§4.E)
17. [ ] Drill log JSON + share sheet (§4.F)
18. [ ] Share result image (§4.D)
19. [ ] First-run onboarding wizard (§7.10)
20. [ ] Walk-the-Range + tap-and-hold identify (§5.A, §5.B)
21. [ ] Group-color preview firmware extension + `[ Preview Groups ]` button (§7.3)

**Gate 3 (ambitious v1 UX — deferrable if field test slips):**
22. [ ] Photo Map identify (§5.C)

**Gate 4 (pre-field-test hardening):**
23. [ ] Transmitter electrical inspection
24. [ ] SW-420 pot re-tune on field-test subset
25. [ ] Battery burn-in (eng §1.9)
26. [ ] Outdoor readability validation on chosen iPhone
27. [ ] Non-Jeremy zero-coaching test

---

### §11 Unresolved — gates on other reviews

- **§7.3 Group-color preview firmware extension** — needs `/plan-eng-review` to validate RF24 payload + serial parser airtime budget for `PREVIEW/`.
- **§5.C Photo Map** — needs `/plan-eng-review` to pick camera package (camera vs image_picker vs native), iOS photo storage (app docs vs PHPhotoLibrary), permission flow, size budget.
- **§7.2 Auto-theme lux thresholds (1000/200)** — design hypothesis; validate at Gate 4 outdoor test; adjust if overcast/golden-hour behavior is wrong.
- **Sim Daltonism pass** on group-color palette (§7.3) before firmware palette lock — magenta/purple may confuse under deuteranope CVD.

---

*End of Design Review Addendum v2 — 2026-04-20*

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | CLEAR (2026-04-19) | SCOPE_EXPANSION · 7 proposals · 7 accepted · 0 deferred |
| Codex Review | `/codex review` | Independent 2nd opinion | 2 | issues_found (2026-04-20) | 8 findings · 6 accepted · 1 deferred · 1 partial |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (PLAN) (2026-04-20) | 21 issues · 1 accepted v1 risk (SW-420 missed-hit) |
| Design Review | `/plan-design-review` | UI/UX gaps | 2 | CLEAR (v2, 2026-04-20) | v1 discarded (wrong priors) · v2 score 5/10 → 9/10 · 20+ decisions locked · Gate-1-first aligned with eng |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | n/a (no external dev audience in v1) |

**CROSS-MODEL:** Design review v2 reconciles against CEO + eng docs; no unresolved tensions. Codex CORE problem (on-range target-identity mapping) addressed by §5 with both tap-and-hold and photo-based flows.

**UNRESOLVED:** 3 items
- §7.3 firmware airtime budget for `CMD_PREVIEW` (gate: `/plan-eng-review`)
- §5.C camera package + iOS photo storage (gate: `/plan-eng-review`)
- §7.2 auto-theme lux thresholds (gate: outdoor field test in Gate 4)

**VERDICT:** CEO + ENG + DESIGN ALIGNED — ready to execute Gate 1. Gate 2 expansions queued. §7.3 and §5.C firmware/eng gates must clear before their tasks land.

