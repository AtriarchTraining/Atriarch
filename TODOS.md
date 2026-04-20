# TODOS

Deferred work captured during planning. These are NOT committed for v1 but are
explicitly tracked so they don't silently drop.

---

## v2 hardware

### Accelerometer upgrade (Approach C from 2026-04-19 design doc)
- **What:** Replace SW-420 hit detection with a MEMS accelerometer (LIS3DH or equivalent) plugged into the unused LCD header (P7, I2C).
- **Why:** SW-420 binary vibration switch cannot discriminate wind-induced cardboard flex from bullet impact. Field test credibility depends on sensor reliability.
- **Pros:** Definitive sensor fix. Firmware sensor abstraction (landed in v1) makes this a clean swap.
- **Cons:** 30-unit hardware rework. Part selection, level-shifting, mechanical mounting all open. Risk of bad solder joints.
- **Context:** v1 firmware ships with `hit_sensor.h` interface + `sw420.cpp` implementation. v2 adds `lis3dh.cpp` and flips the build flag. Prototype on 2-3 units first, capture bullet-impact vs wind waveforms, set thresholds, then pilot batch (~5), then full rollout.
- **Depends on:** v1 field test results (un-defer trigger: wind FPs sink trainer experience).

### LIS3DH part selection + characterization
- **What:** Evaluate LIS3DH vs MPU-6050 vs LSM6DS3 for hit detection. Use the `firmware/bench/target_accel_test/` sketch (already has auto-detect + CSV logging) to capture real bullet-impact waveforms on cardboard.
- **Why:** Part choice determines firmware DSP strategy (tap-detect ISR vs continuous polling).
- **Depends on:** v1 field test complete.

### LCD header wiring confirmation
- **What:** Confirm P7 header carries SDA/SCL routed to ATmega328P's TWI pins (A4/A5). Confirm 3.3V vs 5V rail and whether level shifting is needed.
- **Why:** Unknown today; blocks v2 hardware rework.

### Mechanical mounting of accelerometer in target enclosure
- **What:** Coupling to cardboard mount matters as much as sensor choice. Needs physical prototype and vibration testing.
- **Why:** Biggest unknown in sensor upgrade.

### Target identity self-report + pairing journal (codex #6)
- **What:** Target emits `EVT_BOOT/<node_addr>/<fw_version>/` on power-up. Transmitter logs duplicates or unexpected addresses. App's pairing step records "this physical unit is ID X" in a Hive box keyed on a per-unit random token.
- **Why:** Compile-time `NODE_ADDRESS` means a reflashed unit poisons presets/history/logs silently. Not a field-test blocker (addresses are stable across v1 fleet) but becomes critical when multiple trainers or replacement units enter the picture.
- **Depends on:** Hive schema v1 (v1), any multi-unit identity conflict.

---

## v2 app

### Cross-platform BLE (Android)
- **What:** Android build with flutter_blue_plus Android reconnect path (autoConnect + background handling).
- **Why:** v1 is iPhone-only per CEO. Android is required to reach other trainers.
- **Pros:** Broader market.
- **Cons:** FBP Android quirks (GATT 133 errors, autoConnect timing), UI adjustments.

### Drill history across days/sessions
- **What:** Persisted history spanning multiple app launches and days, with filtering/search.
- **Why:** v1 only shows current session. Trainers will want week-over-week review.
- **Depends on:** Hive schema evolution; may need sqflite migration for query scale.

### One-handed gesture controls for drill abort (from CEO deferral)
- **What:** Shake, long-press, or volume-button shortcut to trigger STOP without looking at screen.
- **Why:** Trainer has hands full; getting to STOP button costs seconds that matter on a range.

### Student-facing lane timer large display (from CEO deferral)
- **What:** Secondary view on the phone (or a paired tablet) showing a huge timer for students.
- **Why:** Social/competitive drill format. Not field-test-critical.

### Voice commands "start drill" "reset" (from CEO deferral)
- **What:** Speech-to-text wake word + command recognition.
- **Why:** Hands-free trainer operation.
- **Cons:** iOS speech APIs + outdoor noise + ear-pro headsets make this hard.

### AI-driven drill generation (from CEO deferral)
- **What:** Generate drills based on skill level / student goals.
- **Why:** Differentiator. Not v1 scope.

### Student companion app (from CEO deferral)
- **What:** Student-side app showing their own per-drill stats, leaderboard, history.
- **Why:** Multi-user expansion. Out of scope until trainer adoption proven.

### Photo-based target identify (from 2026-04-20 design review)
- **What:** Trainer takes one photo of the range, taps each target in the photo, app associates screen coordinates with target IDs. Later, tapping a target position in the photo triggers CMD_IDENTIFY on that unit.
- **Why:** Eliminates downrange walking round-trips. Today (v1): 4 round-trips per target identification. With photo-based: 0 walks after the initial photo.
- **Pros:** Big trainer-experience win. Scales to 30 targets without pain.
- **Cons:** Coordinate capture + tap-region UI is non-trivial. Needs camera permission flow. Phones + range = grease, dust, dropped devices. Range photo may change between sessions (targets moved, swapped) — needs "retake" flow.
- **Context:** v1 ships with "tap-and-hold chip = repeated CMD_IDENTIFY while held" — a simpler pattern that still reduces round-trips from 4 to 1. Photo-based is the v2 aspiration.
- **Depends on:** v1 field test validates whether tap-and-hold is sufficient. If trainers still complain about walking, photo-based becomes v2 scope.

### Practiscore / IPSC scoring integration (from CEO deferral)
- **What:** Export to scoring platforms used in competitive shooting.
- **Why:** Hooks into existing community workflows.

### Per-target runtime threshold tuning
- **What:** App UI to adjust vibration threshold / debounce per target, stored in Hive.
- **Why:** Today thresholds are compile-time `#define`s. Different physical environments (wind, mount variance) need different settings.
- **Depends on:** Wire protocol extension (CONFIG/ command); firmware persistence in EEPROM.

---

## v2 infra / process

### Second transmitter as hot spare
- **What:** Build a second hand-wired transmitter (or design Rev 2 board) so the field test isn't a single point of failure.
- **Why:** Design doc explicitly calls out transmitter SPOF as a risk. For v1, mitigation is pre-class inspection. v2 mitigation is a spare.

### Multi-range / cloud sync
- **What:** Drill templates, session history, target rosters synced across multiple ranges via cloud.
- **Why:** Trainer with two locations. Out of scope for v1.

### Productization: manufacturing, BOM, packaging, pricing
- **What:** Everything past beta. Target PCB Rev 2 with integrated accelerometer, enclosure design for manufacturability, unit pricing, channel strategy.
- **Why:** Out of scope until trainer validation evidence from v1 field test.

### ISR-driven sensor polling (v2 with accelerometer)
- **What:** Switch from `pulseIn()` polling to hardware interrupt on INT1 pin (LIS3DH tap-detect).
- **Why:** Lowers CPU load, improves timing precision. Free with v2 accelerometer swap.
- **Depends on:** Accelerometer upgrade.
