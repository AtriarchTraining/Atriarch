---
status: ACTIVE — Phases 1+2 complete (2026-04-20); Phase 3 agent dispatched
installed:
  esp32_core: 3.3.8
  nimble_arduino: 2.5.0
  fqbn: esp32:esp32:esp32
verification:
  phase_1_toolchain: PASS (esp32 core + NimBLE installed, FQBN resolves)
  phase_1_blink_test: PASS (ESP32 D0WD-V3 rev 3.1 MAC f4:2d:c9:6a:9b:08, blink sketch uploaded and running)
  phase_2_hardware: PASS (NRF24 probe sketch confirmed isChipConnected=true; fast-blink visual confirmed by Jeremy)
---

# ESP32 Transmitter Port Plan (Gate 1 #10.5)

**Generated:** 2026-04-20 from `feature/system-v2` (main worktree)

**Addresses:** The 171%-of-2KB-RAM ceiling hit when Gate 1 firmware was compiled for the ATmega328P transmitter. Target firmware fits (39% RAM). Only the transmitter swaps hardware.

**Upstream context:**
- CEO doc: `~/.gstack/projects/AtriarchTraining-Atriarch/jeremygill-feature-system-v2-design-20260419-133046.md`
- Eng plan: `~/.gstack/projects/AtriarchTraining-Atriarch/eng-plans/2026-04-20-atriarch-v2-engineering-plan.md` (§1.15 Program B SRAM audit became urgent → this doc is the answer)
- Implementation plan: `docs/superpowers/plans/2026-03-31-atriarch-implementation.md` (addendum §10 Gate 1 #10 "one drill end-to-end works")

---

## Prerequisites

Hardware arriving 2026-04-20 evening (Amazon Prime Today, 5–10 PM):

- 1× **HiLetgo ESP32-WROOM-32 USB-C DevKit** (from a 3-pack; 2 spares for future hot-spare work)
- 1× **KeeYees JESSINIE USBasp programmer** (2-pack, unchanged purpose — still flashes targets)
- 1× **CP2102 USB-to-TTL adapter** (optional; target-side serial debug if needed)
- 1× **USB-C to USB-A female adapter** (for USBasp + CP2102 into Mac mini USB-C)

Already on hand:
- NRF24L01 module on existing breadboard
- 10µF / 22µF decoupling cap across NRF24's VCC-GND (REQUIRED — if not present, add one; ESP32's 3.3V regulator needs the reservoir for NRF24 TX bursts)
- iPhone 16 Pro Max USB-C cable (Mac ↔ ESP32 direct)
- Mac mini (USB-C only, macOS 26.4), `arduino-cli` 1.4.1 installed, `flutter` 3.41.6

---

## Scope

### Changes
- Transmitter hardware: Arduino Nano + HM-10 BLE module → single **ESP32-WROOM-32**
- Transmitter firmware: `SoftwareSerial`-to-HM-10 transport → **ESP32 native BLE peripheral** (NimBLE-Arduino)
- Build target: `arduino:avr:nano` → `esp32:esp32:esp32`
- RAM headroom: 2 KB ceiling → 520 KB (effectively gone as a concern for all of Gate 1/2/3)

### Does NOT change
- **BLE service/characteristic UUIDs** stay at the HM-10 values (`0000ffe0-0000-1000-8000-00805f9b34fb` / `0000ffe1-0000-1000-8000-00805f9b34fb`) → app needs zero UUID-level code change
- The serial parser state machine in `transmitter.ino` (just swap the byte-source transport)
- Text protocol: `A/.../`, `B/.../`, `STOP/`, `STOP_ACK/`, `SNAP/`, `SNAP_REPLY/`, `D/`, `DDONE/`, `ACT/`, `HIT/`, `DONE/`, `NS/`, `LATE/`, `FIN/`, `ERR/unreachable/` — unchanged
- NRF24 protocol to targets (MSG_SIZE=4, EVT_ACK, EVT_HB, CMD_ACTIVATE, etc.) — unchanged
- **All target PCBs and target firmware stay untouched**

---

## Phase 1 — Toolchain setup (can start before hardware arrives)

Runs from the main worktree in this Claude session. ~5 minutes.

```bash
arduino-cli core install esp32:esp32
arduino-cli lib install "NimBLE-Arduino"
arduino-cli board listall esp32  # confirm esp32:esp32:esp32 FQBN is valid
```

**Acceptance:**
- `esp32:esp32` core installed (expect ~500 MB download: xtensa-esp32-elf toolchain, esptool, etc.)
- `NimBLE-Arduino` library installed (current stable: 2.2.x)
- `arduino-cli board listall esp32` lists `esp32:esp32:esp32` as "ESP32 Dev Module"

---

## Phase 2 — Hardware rewiring (human, when ESP32 arrives)

### Remove
- Arduino Nano from breadboard
- HM-10 BLE module (and its voltage divider on RX if present — ESP32 is 3.3V logic, no divider needed anywhere)

### Keep
- NRF24L01 module on its current position
- Decoupling cap across NRF24 VCC/GND

### Add
- ESP32-WROOM-32 DevKit seated across the breadboard's center gutter (straddles the gap, pins accessible both rows)

### Wire: NRF24L01 → ESP32 GPIO (VSPI default pinout)

| NRF24L01 pin | ESP32 GPIO | Notes |
|---|---|---|
| VCC | 3.3V (labeled `3V3` on DevKit) | Not 5V — NRF24 is 3.3V-only |
| GND | GND | Any ground rail |
| CE | GPIO 22 | Chip Enable |
| CSN | GPIO 21 | Chip Select |
| SCK | GPIO 18 | VSPI clock (default) |
| MOSI | GPIO 23 | VSPI MOSI (default) |
| MISO | GPIO 19 | VSPI MISO (default) |
| IRQ | (unconnected) | RF24Network doesn't use IRQ |

### Power path
- ESP32 DevKit gets 5V via USB-C from Mac mini
- Onboard AMS1117-3.3 regulator steps down to 3.3V for the ESP32 chip
- 3.3V rail is brought out to the breadboard header → powers NRF24
- If NRF24 transmission glitches (resets, missed packets under load): add a second 10µF electrolytic cap near the ESP32's 3.3V pin as well

**Acceptance:** ESP32 boots (onboard red LED solid, blue LED may blink per firmware); NRF24 not visibly damaged; no smoke.

---

## Phase 3 — Firmware port

**Strategy:** create `firmware/transmitter_esp32/` as a new sketch. Keep `firmware/transmitter/` (the Nano version) as reference until ESP32 runs a drill end-to-end, then archive the old.

### Files

```
firmware/transmitter_esp32/
├── transmitter_esp32.ino   # main sketch, BLE peripheral setup, loop()
├── config.h                # constants, pin map, UUIDs
├── serial_parser.h         # VERBATIM copy from firmware/transmitter/
├── ble_transport.h         # NEW: NimBLE peripheral wrapper (in + out)
└── ble_transport.cpp       # NEW
```

### config.h changes from Nano version

```cpp
// --- Pin Definitions (ESP32) ---
#define NRF_CE_PIN      22
#define NRF_CSN_PIN     21
#define NRF_SCK_PIN     18
#define NRF_MOSI_PIN    23
#define NRF_MISO_PIN    19

// --- BLE (replaces HM-10 serial) ---
#define BLE_DEVICE_NAME       "Atriarch-TX"
#define BLE_SERVICE_UUID      "0000ffe0-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_UUID         "0000ffe1-0000-1000-8000-00805f9b34fb"

// --- All protocol constants stay identical ---
#define MSG_SIZE              4
#define CMD_ACTIVATE          1
// ... (unchanged from Nano config.h)
```

### ble_transport.h / .cpp

Wrap NimBLE in a small interface that mirrors the Serial API the parser expects:

```cpp
// ble_transport.h
class BleTransport {
public:
  void begin();                              // start BLE server, advertise
  bool available();                          // any inbound bytes buffered?
  int read();                                // pop one inbound byte
  void write(const char* buf, size_t len);   // notify outbound
  void print(const char* s);                 // convenience
  void println(const char* s);               // convenience (appends \n)
private:
  NimBLEServer* server;
  NimBLECharacteristic* characteristic;
  Queue<uint8_t> rxBuffer;                   // filled in onWrite callback
};
```

Inside `onWrite` callback: append received bytes into `rxBuffer`. The existing `serial_parser.h` loop reads byte-by-byte from `BleTransport::read()` instead of `Serial.read()` — parser logic is untouched.

Outbound: every existing `Serial.print("ACT/3/\n")` style call becomes `ble.print("ACT/3/\n");` which internally does `characteristic->setValue(...); characteristic->notify();`.

### transmitter_esp32.ino skeleton

```cpp
#include <NimBLEDevice.h>
#include <SPI.h>
#include <RF24.h>
#include <RF24Network.h>
#include "config.h"
#include "ble_transport.h"
#include "serial_parser.h"

SPIClass vspi(VSPI);
RF24 radio(NRF_CE_PIN, NRF_CSN_PIN);
RF24Network network(radio);
BleTransport ble;
SerialParser parser;

// ... all the existing state: PendingCmd[], GroupState[], lastHbMs[], etc.

void setup() {
  Serial.begin(115200);                      // USB debug only
  Serial.println("Atriarch TX booting...");

  vspi.begin(NRF_SCK_PIN, NRF_MISO_PIN, NRF_MOSI_PIN, NRF_CSN_PIN);
  radio.begin(&vspi);
  network.begin(RF24_CHANNEL, MASTER_ADDRESS);
  radio.setDataRate(RF24_2MBPS);

  ble.begin();                               // starts advertising "Atriarch-TX"
  Serial.println("BLE advertising + NRF24 up");
}

void loop() {
  network.update();
  while (ble.available()) {
    parser.feed((char)ble.read());
    if (parser.hasCommand()) dispatchCommand(parser.takeCommand());
  }
  handleIncomingRf();       // existing
  serviceDrill();           // existing
  serviceAckRetries();      // existing
  serviceHeartbeatTracker();// existing
  serviceStopAggregate();   // existing
}
```

### What stays VERBATIM from the Nano version
- `serial_parser.h` (pure state machine, transport-agnostic)
- `PendingCmd[]` journal + `serviceAckRetries()`
- Heartbeat tracker + `serviceHeartbeatTracker()`
- STOP aggregate + `serviceStopAggregate()`
- `SNAP/` handler
- Drill FSM (`GroupState[]`, `tickGroups()`, etc.)
- RF24-incoming handler

**Where possible, `#include` those files from the Nano sketch directory rather than copy-pasting.** `#include "../transmitter/serial_parser.h"` works in arduino-cli if the sketch root is set correctly.

### Build + flash

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 firmware/transmitter_esp32
arduino-cli board list                                     # find ESP32's port
arduino-cli upload --fqbn esp32:esp32:esp32 --port /dev/cu.usbserial-XXXX firmware/transmitter_esp32
arduino-cli monitor --port /dev/cu.usbserial-XXXX --config baudrate=115200
```

### Acceptance

- Compiles under 20% of 4 MB flash, uses < 20% of 320 KB SRAM (expect ~15%)
- On power-up, USB serial monitor shows `"Atriarch TX booting..."` then `"BLE advertising + NRF24 up"`
- ESP32 advertises `"Atriarch-TX"` — verifiable with any BLE scanner app on phone (e.g., LightBlue) BEFORE running the Atriarch Flutter app

---

## Phase 4 — App integration

**Expected: zero code changes**, because UUIDs match HM-10's.

### Steps

1. On iPhone: Settings → Bluetooth → "Forget" the old HM-10 ("HMSoft") if previously paired — iOS can cache stale pairings and refuse the new device with matching UUID otherwise.
2. `flutter run -d 00008140-000C0D093A98801C` from the main worktree `/Volumes/T7/Atriarch`
3. App lands on Device Discovery → scan list → expect `Atriarch-TX` visible with RSSI
4. Tap it → app connects → lands on Home with green "Connected · Atriarch-TX" banner
5. Home → Program B → tap the SCAN FAB → NRF24 discovery pings 30 addresses → each online target's D/<id>/ arrives, followed by DDONE/

### Possible app-side tweak

Check `lib/services/ble_service.dart` for any name-based filtering (grep for `"HMSoft"` or `contains("HM")`). If found, switch to UUID-only filtering so `Atriarch-TX` passes. Likely already UUID-based — verify first, fix only if needed.

### Acceptance

- iPhone sees `Atriarch-TX` in scan
- App connects, banner turns green
- Scan FAB successfully discovers target fleet

---

## Phase 5 — End-to-end drill test

With 2 targets flashed via USBasp (Gate 1 firmware, unique `NODE_ADDRESS=01` and `02`) and ESP32 transmitter running:

1. iPhone app: Home → Program B → SCAN → expect 2 targets online as chips labeled `T1` and `T2`
2. Set: start 1.0–3.0s, between 0.5–2.0s, required hits 1, iterations 3
3. Tap START → button displays `ARMING…` spinner briefly
4. First `ACT/<id>/` arrives from transmitter → app navigates to Drill Running screen
5. Target lights green → tap it (or physically hit / vibrate-trigger it) → `HIT/` arrives
6. Target completes → transmitter emits `DONE/` → next target activates
7. 3 iterations each × 2 targets = 6 activations, ~20–30 seconds total
8. Transmitter emits `FIN/` → app navigates to Results
9. Verify Results shows per-target table (T1 / T2 rows with hits, completions, avg ms)
10. Tap Run Again → same drill starts fresh → part-way through, press-and-hold STOP for 800ms → enters `STOPPING…` → `STOP_ACK/` arrives → lands on Results

### Acceptance

- Full drill loop works with ESP32 transmitter
- No BLE disconnects, no stuck/unreachable targets during a clean test
- STOP verified safe in every phase (arming, running, near-complete)

---

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| ESP32's 3.3V regulator can't supply NRF24 TX peak current | Medium | Decoupling cap; add second cap if glitches observed |
| `RF24` library timing differs between AVR and ESP32 | Low | Library supports ESP32 officially; `setRetries(5,15)` + `setAutoAck(true)` stay the same; only difference is SPI object pass-through |
| NimBLE-Arduino version incompatibility with esp32 core | Low | Pin to NimBLE-Arduino 2.2.x and esp32 core 3.x in this plan (both current) |
| iPhone caches old HM-10 pairing with same UUIDs | Low | Forget HM-10 in iOS Bluetooth settings before first ESP32 connect |
| `/dev/cu.usbserial-XXXX` port name differs between devkits | Certain | `arduino-cli board list` identifies it each time; wrap in a shell var |
| ESP32 BLE MTU < 23 bytes fragments Program A commands | Low | NimBLE negotiates MTU up to 247 by default; keep 20-byte-chunk-safe writes on the app side for v1 (matches existing HM-10 behavior) |

---

## Agent dispatch strategy

**Phase 1 — drive directly from this Claude session.** ~5 min. No agent, no worktree needed. Main worktree is fine.

**Phase 2 — human hands only.** Physical rewiring.

**Phase 3 — dispatch one focused agent.** Prompt includes this plan path + explicit scope: create `firmware/transmitter_esp32/`, port per the file skeleton above, compile, flash, serial-verify boot + BLE advertising. 60–90 min session. Isolated worktree optional; committing to `feature/system-v2` directly is fine since the gate-2 tab touches `lib/` not `firmware/`.

**Phases 4 + 5 — interactive in this Claude session.** Tandem driving: I run `flutter run` + ESP32 serial monitor; you drive the phone UI and physical targets.

---

## Deliverables per phase

| Phase | Artifact | Commit |
|---|---|---|
| 1 | ESP32 core + NimBLE installed locally | `chore: install esp32 arduino-cli toolchain` (or just a note in the plan) |
| 2 | (none; hardware only) | — |
| 3 | `firmware/transmitter_esp32/` compiles + flashes + BLE-advertises | `feat(firmware): port transmitter to ESP32 (Gate 1 #10.5)` |
| 4 | App connects to `Atriarch-TX`, scan works | (no commit — just verification) or a 1-line UUID filter fix if needed |
| 5 | End-to-end drill succeeds | `feat: Gate 1 #10 — ESP32 transmitter + 2-target Program B end-to-end verified` |

---

*End of plan — 2026-04-20*
