# Target Firmware Reflash & Protocol Verification

Date: 2026-05-11
Type: Hardware/firmware deployment playbook (not a code-change plan)
Status: Ready to execute

## Goal

Flash the current `firmware/target/target.ino` to every beta target ATmega328 and verify that the full app↔transmitter↔target protocol works end-to-end on real hardware.

This unblocks the **Flash LED** button shipped in PR #2 (target setup screen) — the app side is correct, but beta units are running factory pre-protocol firmware that doesn't handle `CMD_IDENTIFY`.

## Prerequisites

- One beta transmitter (Arduino Nano + HM-10 BLE + NRF24L01) — already known working with the app.
- Beta target unit(s) — Target PCB Ver 1.0 (ATmega328 DIP + NRF24 + relay + WS2812 + SW-420 vibration sensor).
- Mac with Arduino IDE 2.x installed.
- USB cable + at least one of:
  - **USB-to-serial adapter** (FTDI FT232 or CP2102) — if PCB has serial header + bootloader.
  - **ISP programmer** (USBasp, USBtinyISP, or another Arduino as ISP) — if no bootloader.
- The transmitter app installed and connected (the PR #2 setup screen is the test surface).

## Phase A — Identify the programming path (per-unit, one-time)

Open one beta target unit (or check schematics if you have them) and look for:

- [ ] **6-pin serial header** labeled with `TX/RX/GND/VCC/DTR` (or similar) → bootloader path (Phase B).
- [ ] **6-pin ICSP/ISP header** labeled `MISO/MOSI/SCK/RST/VCC/GND` (2x3 layout) → ISP path (Phase C).
- [ ] Both headers present → either works; bootloader is faster.
- [ ] Neither header → you'll need to lift the chip and program it externally (out of scope here — escalate).

Notes:
- If a serial header exists but you don't know whether a bootloader is flashed, try Phase B first. If it fails to upload with "not in sync" or similar, fall back to Phase C.
- Photograph the headers and trace the pins to confirm pinout before connecting power.

## Phase B — Flash via USB-to-serial (bootloader path)

### Setup

- [ ] In Arduino IDE: `Tools → Board → Arduino AVR Boards → Arduino Nano` (or `Uno` — they share ATmega328P).
- [ ] `Tools → Processor → ATmega328P` (or `ATmega328P (Old Bootloader)` if upload fails with the default).
- [ ] `Tools → Port → /dev/cu.usbserial-*` (your FTDI/CP2102 port).
- [ ] Install required libraries: `Sketch → Include Library → Manage Libraries → install: RF24, RF24Network, FastLED`.

### Wiring (target board powered OFF)

- [ ] FTDI `GND` → target serial-header `GND`
- [ ] FTDI `VCC` (3.3V or 5V to match board) → target `VCC`
- [ ] FTDI `TX` → target `RX`
- [ ] FTDI `RX` → target `TX`
- [ ] FTDI `DTR` → target `DTR/RST` (this is what triggers auto-reset for upload)
- [ ] Plug the FTDI into the Mac. Confirm port appears in `ls /dev/cu.usbserial-*`.

### Per-target flash

- [ ] Open `firmware/target/target.ino` in Arduino IDE.
- [ ] Open `firmware/target/config.h` (or wherever `NODE_ADDRESS` is defined). **Set `NODE_ADDRESS` to the unique target id you want this unit to claim** (1, 2, 3 for your three beta units). This is the value the app sees as "Target N".
- [ ] Compile (`Sketch → Verify/Compile`). Expected: clean compile.
- [ ] Upload (`Sketch → Upload`). Expected: "Done uploading" within ~10s, no `avrdude: stk500_getsync()` errors.
- [ ] Open Serial Monitor at 9600 baud. Expected: target boots, prints any boot banner the firmware emits.
- [ ] Power-cycle the unit (unplug FTDI VCC → replug) and confirm the WS2812 lights briefly on boot.
- [ ] Repeat for each target with the next `NODE_ADDRESS`. **Do not leave two targets on the same NODE_ADDRESS** — discovery collisions look like random offlines.

If upload fails:
- "`stk500_getsync()`" → wrong port, bad wiring, or no bootloader → fall back to Phase C.
- "`programmer is not responding`" → DTR not wired (try pressing RST manually right before upload begins).
- Compile fails on missing library → re-check `RF24`, `RF24Network`, `FastLED` are installed.

## Phase C — Flash via ISP (no-bootloader path)

### Setup (Arduino-as-ISP option, since you have spare Nanos)

- [ ] Open `File → Examples → 11.ArduinoISP → ArduinoISP` in Arduino IDE.
- [ ] Select a spare Nano as the board, upload `ArduinoISP` to it. This Nano is now your programmer.
- [ ] Wire the programmer Nano ↔ target ISP header (target powered OFF):
  - Programmer D10 → target RST
  - Programmer D11 (MOSI) → target MOSI
  - Programmer D12 (MISO) → target MISO
  - Programmer D13 (SCK) → target SCK
  - Programmer 5V → target VCC
  - Programmer GND → target GND
- [ ] Optional but recommended: 10µF cap between programmer RESET and GND to keep it from auto-resetting during upload.

### Per-target flash

- [ ] In Arduino IDE: `Tools → Board → Arduino Nano`, `Tools → Programmer → Arduino as ISP` (NOT "ArduinoISP" — different option).
- [ ] Optional: `Tools → Burn Bootloader` if you want bootloader installed for easier future uploads (skips if you want to stay ISP-only).
- [ ] Open `firmware/target/target.ino`, set unique `NODE_ADDRESS` per unit.
- [ ] `Sketch → Upload Using Programmer` (Ctrl/Cmd-Shift-U — NOT regular Upload).
- [ ] Expected: avrdude reports `bytes of flash written` and `verified`. ~10–30s per unit.
- [ ] Power-cycle and confirm WS2812 boot indicator.

If "`avrdude: device signature 0x000000`" or `0xffffff`:
- Wiring issue or target ATmega is missing/dead. Reseat the chip and re-check ISP pinout.

If "`out of sync`":
- Bad SPI wiring or wrong programmer selected.

## Phase D — Bench protocol verification

Bring all reflashed targets + transmitter + iPhone (with the app from PR #2) to a single bench. Targets need their normal power source.

### D.1 — Discovery

- [ ] Power on transmitter (USB to iPhone or independent USB power).
- [ ] Power on all targets.
- [ ] Open the app, connect to transmitter (top of home screen).
- [ ] Open **TARGET SETUP**.
- [ ] Expected: within ~2s of entering the screen, "**N of N targets online**" appears, where N = number of powered-on targets.
- [ ] Tap **RESCAN**. Expected: same N of N, no flicker to 0.
- [ ] Power off one target. Tap **RESCAN**. Expected: that target's row stays in the list but the dot goes dim and subtitle reads `offline`. Other targets stay online.
- [ ] Power it back on, **RESCAN**. Expected: comes back online.

### D.2 — Identify (the original blocker)

- [ ] Tap the **⚡ Flash LED** button on Target 1's row.
- [ ] Expected: "Flash sent to Target 1" snackbar **and** Target 1's WS2812 flashes white several times (default `IDENTIFY_FLASHES` per firmware). Other targets do nothing.
- [ ] Repeat for each target. Confirm only the addressed target flashes — no cross-talk.
- [ ] Try **WALK_THE_RANGE** at the bottom of the screen. Expected: each online target flashes in turn with a TTS readout of its name (2s between targets).

### D.3 — Drill cycle

- [ ] Back out to home, open **PROGRAM A**.
- [ ] Assign targets to groups (if you've already set persistent groups via TARGET SETUP, they pre-populate).
- [ ] Start a drill. Expected: targets ACTIVATE (relay clicks, WS2812 may indicate per firmware), then on a vibration hit → HIT event → DEACTIVATE within `LATE_HIT_FLASH_MS` budget.
- [ ] Stop drill. Expected: all targets DEACTIVATE within ~800ms (per the safety-critical fix in your memory).
- [ ] Open **RESULTS**. Expected: hit timestamps, splits, transitions all populate.

### D.4 — Heartbeat / unreachable

- [ ] Start a drill with N targets, then physically pull power on one target mid-drill.
- [ ] Expected: app surfaces that target as `unreachable` within ~3 missed heartbeats. Drill continues for the rest.
- [ ] Restore power. Expected: it rejoins on the next drill.

### D.5 — Sign-off

- [ ] Discovery: ✅
- [ ] Identify (per-target + walk-the-range): ✅
- [ ] Drill cycle (activate → hit → deactivate, STOP within 800ms): ✅
- [ ] Heartbeat / unreachable: ✅

If any row fails, capture serial monitor output from the target + transmitter and file the failure mode. **Do not** start rewriting the app — the protocol is the contract; failures here are firmware bugs on the just-flashed target.

## After verification

- [ ] Comment on PR #2 confirming flash button works on real hardware.
- [ ] Optionally land PR #2 if it hasn't been merged yet.
- [ ] If `firmware/target/target.ino` had to be patched during this exercise (e.g., a real bug found during D.2 / D.3), commit those fixes to a separate firmware branch and PR them in.

## Out of scope

- The full firmware rewrite (separate, larger effort already approved in your memory). This playbook flashes what's in the repo *today* and verifies the existing protocol works end-to-end. If the rewrite happens later, repeat Phase D against the new firmware as the regression checklist.
- Battery indicator — hardware mod required first.
- OTA updates — separate spec (`2026-05-11-ota-firmware-updates.md` already exists in `docs/superpowers/plans/`).

## Risks

- **NODE_ADDRESS collision** if you forget to change it per-target. Symptom: targets randomly drop offline or hits attribute to the wrong target. Always verify each target's claimed id via the setup screen after flashing.
- **Brown-out reset** during ISP if VCC is shared between programmer and powered target — keep target unpowered during flash and use programmer 5V only.
- **Lifting traces** with bad probing — solder a header onto the PCB once rather than holding probes against pads for repeated flashes.
