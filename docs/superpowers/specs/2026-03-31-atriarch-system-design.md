# Atriarch Reactive Target Training System — System Design Spec

**Date:** 2026-03-31
**Status:** Approved
**Scope:** Complete system — Flutter app, transmitter firmware, target firmware

---

## 1. Product Overview

Atriarch is a wireless reactive target training system for shooting, reaction, law enforcement, and competition-style drills. An instructor configures a drill on a phone/tablet app, which sends commands via BLE to a central transmitter. The transmitter orchestrates target activations via NRF24L01 radio. Targets detect hits via vibration sensors and report events back through the transmitter to the app.

### System Topology

```
┌─────────────┐     BLE/UART      ┌──────────────┐     NRF24      ┌──────────┐
│  Flutter App │ ────────────────→ │ Transmitter  │ ──────────────→│ Targets  │
│             │  A/.../  B/.../   │ ATmega328P   │  CMD_ACTIVATE  │ (up to   │
│  Config     │  STOP/  DISC/    │ + HM-10 BLE  │  CMD_DEACTIVATE│  30 units)│
│  Timer+Stop │ ←──────────────── │ + NRF24L01   │ ←──────────────│ Arduino  │
│  Results    │  ACT/ HIT/ NS/   │              │  EVT_HIT       │ Nano     │
│             │  LATE/ FIN/ D/   │  State machine│  EVT_COMPLETE  │ +NRF24   │
└─────────────┘                   │  per group   │  EVT_NOSHOOT   │ +WS2812  │
                                  └──────────────┘  EVT_LATE      │ +vibSens │
                                                                   └──────────┘
```

### Hardware Constraints (FROZEN — do not change)

- **Transmitter:** ATmega328P + HM-10/HM-19 BLE serial module + NRF24L01 radio
- **Targets:** Arduino Nano-class MCU + NRF24L01 radio + WS2812 LED strip (6 LEDs) + vibration sensor + 12V relay + manual power switch
- **BLE link:** Phone ↔ Transmitter (service UUID `0000ffe0-0000-1000-8000-00805f9b34fb`, characteristic UUID `0000ffe1-0000-1000-8000-00805f9b34fb`)
- **NRF24 link:** Transmitter ↔ Targets (RF24Network, channel 90, 2Mbps, octal tree addressing)

---

## 2. RF24 Network Addressing

RF24Network uses a tree topology with octal addresses. The transmitter is the root node.

```
Node 00 (transmitter)
├── 01 (target, also relays for children)
│   ├── 011, 021, 031, 041, 051
├── 02 (target, also relays for children)
│   ├── 012, 022, 032, 042, 052
├── 03 (target, also relays for children)
│   ├── 013, 023, 033, 043, 053
├── 04 (target, also relays for children)
│   ├── 014, 024, 034, 044, 054
└── 05 (target, also relays for children)
    └── 015, 025, 035, 045, 055
```

**Capacity:** 5 level-1 + 25 level-2 = 30 targets max.

**Routing constraint:** Level-1 targets (01–05) must be powered on for their children to be reachable. Messages to level-2 nodes route through their level-1 parent.

### Target Addressing

- Each target is flashed with a unique `NODE_ADDRESS` constant (the only difference between units).
- All targets run otherwise identical firmware.
- The app discovers online targets via a scan and lets the user identify them (flash LED).
- Logical group assignment is dynamic — configured in the app at drill setup, not burned into firmware.

### Address Representation in Protocol

RF24Network uses octal addresses internally (01, 011, 021, etc.). To avoid confusion in the BLE serial protocol, all target addresses are represented as **decimal integers** in app↔transmitter messages. The transmitter maps these to octal RF24Network addresses.

| Decimal ID | Octal RF24 Address | Tree Position |
|------------|-------------------|---------------|
| 1–5 | 01–05 | Level 1 (also relays) |
| 6–10 | 011, 021, 031, 041, 051 | Level 2, children of 01 |
| 11–15 | 012, 022, 032, 042, 052 | Level 2, children of 02 |
| 16–20 | 013, 023, 033, 043, 053 | Level 2, children of 03 |
| 21–25 | 014, 024, 034, 044, 054 | Level 2, children of 04 |
| 26–30 | 015, 025, 035, 045, 055 | Level 2, children of 05 |

The transmitter firmware contains this mapping table. The app and protocol only ever use decimal IDs 1–30.

### Target Replacement

If a target is destroyed, any spare target (regardless of address) can replace it. The user simply removes the dead target from its group in the app and adds the spare. Recommended: keep a few spares flashed with high decimal IDs (e.g., 26–30) as universal replacements.

---

## 3. Protocol Specification

### 3.1 App → Transmitter (BLE Serial, UTF-8 strings)

All commands are UTF-8 strings terminated with `/`.

#### Discovery

| Command | Format | Description |
|---------|--------|-------------|
| Discover | `DISC/` | Scan all 30 addresses for online targets |
| Identify | `IDENT/<addr>/` | Flash LED on specific target for physical identification |

#### Drill Start — Program A (Grouped Student Mode)

```
A/<startMin>/<startMax>/<delayMin>/<delayMax>/<hitsMin>/<hitsMax>/<g1>/<g2>/<g3>/<g4>/<g5>/<ns>/<iter>/
```

| Field | Type | Description |
|-------|------|-------------|
| startMin/startMax | float (seconds) | Random delay before first activation |
| delayMin/delayMax | float (seconds) | Random delay between activations within a group |
| hitsMin/hitsMax | int | Random required hit count per activation |
| g1–g5 | comma-separated ints | Target addresses in each group (0 = unused group) |
| ns | comma-separated ints | Target addresses designated as no-shoot (0 = none) |
| iter | int | Number of iterations per group (0 = unlimited until STOP) |

Example:
```
A/1.00/3.00/0.50/2.00/2/4/1,11,21/2,12/3/0/0/11,12/10/
```
Meaning: Groups 1–3 active, Group 1 has targets 01/011/021, Group 2 has 02/012, Group 3 has 03. Targets 011 and 012 are no-shoot. 10 iterations per group.

#### Drill Start — Program B (Individual Student Mode)

```
B/<startMin>/<startMax>/<delayMin>/<delayMax>/<hitsMin>/<hitsMax>/<targets>/<ns>/<iter>/
```

| Field | Type | Description |
|-------|------|-------------|
| startMin–hitsMax | same as Program A | |
| targets | comma-separated ints | All participating target addresses |
| ns | comma-separated ints | No-shoot target addresses (0 = none) |
| iter | int | Iterations per target |

Example:
```
B/1.00/2.00/0.50/1.50/1/3/1,2,3,4,5,11,12,13,14,15/5,14/5/
```
Meaning: 10 targets, each operating as its own lane. Targets 05 and 014 are no-shoot. 5 iterations each.

#### Stop

| Command | Format | Description |
|---------|--------|-------------|
| Stop | `STOP/` | Immediately halt all drill activity |

### 3.2 Transmitter → Targets (NRF24, int arrays)

Sent as fixed-size int arrays via RF24Network.

#### Command constants

```c
#define CMD_ACTIVATE    1
#define CMD_DEACTIVATE  2
#define CMD_IDENTIFY    3
#define CMD_PING        4
```

#### Command payloads

| Command | Array | Description |
|---------|-------|-------------|
| Ping | `{CMD_PING}` | Discovery — are you alive? |
| Identify | `{CMD_IDENTIFY}` | Flash LED white 3x |
| Activate (normal) | `{CMD_ACTIVATE, requiredHits, 1}` | Activate as shoot target |
| Activate (no-shoot) | `{CMD_ACTIVATE, 0, 2}` | Activate as no-shoot target |
| Deactivate | `{CMD_DEACTIVATE}` | Force target off |

### 3.3 Targets → Transmitter (NRF24, int arrays)

#### Event constants

```c
#define EVT_PONG         10
#define EVT_HIT          11
#define EVT_COMPLETE     12
#define EVT_NOSHOOT_HIT  13
#define EVT_LATE_HIT     14
```

#### Event payloads

| Event | Array | Description |
|-------|-------|-------------|
| Pong | `{EVT_PONG, nodeAddress}` | Response to ping |
| Hit | `{EVT_HIT, hitNumber, timestampMs}` | Vibration hit detected |
| Complete | `{EVT_COMPLETE, totalHits, totalTimeMs}` | Required hits reached, target self-deactivated |
| No-shoot violation | `{EVT_NOSHOOT_HIT, timestampMs}` | Hit on a no-shoot target |
| Late hit | `{EVT_LATE_HIT, timestampMs}` | Hit after deactivation (during cooldown) |

`timestampMs` = milliseconds since activation (using `millis()` delta).

### 3.4 Transmitter → App (BLE Serial, UTF-8 strings)

Telemetry relayed to the phone. App accumulates silently during drill, displays in results screen.

| Message | Format | Description |
|---------|--------|-------------|
| Target discovered | `D/<addr>/` | One per online target during scan |
| Discovery done | `DDONE/` | End of scan |
| Target activated | `ACT/<addr>/` | Target is now lit |
| Hit detected | `HIT/<addr>/<hitNum>/<requiredHits>/` | Vibration hit on shoot target |
| Target complete | `DONE/<addr>/<totalTimeMs>/` | Target deactivated (hits reached) |
| No-shoot violation | `NS/<addr>/` | Hit on a no-shoot target |
| Late hit | `LATE/<addr>/` | Hit after deactivation |
| Drill finished | `FIN/` | All iterations complete |
| Error | `ERR/<code>/<detail>/` | e.g., `ERR/TARGET_LOST/03/` |

---

## 4. Drill Orchestration Logic (Transmitter)

### 4.1 Program A — Grouped Student Mode

The transmitter runs a **non-blocking state machine per group**. No `delay()` calls — all timing uses `millis()` comparisons in the main loop.

```
Per-group state machine:

WAITING_START → (startDelay expires) → SELECT_TARGET
SELECT_TARGET → pick random eligible target from group
                → determine normal vs no-shoot
                → send CMD_ACTIVATE
                → relay ACT/<addr>/ to app
                → go to WAITING_COMPLETE
WAITING_COMPLETE → receive EVT_COMPLETE or EVT_NOSHOOT_HIT
                  → relay events to app
                  → decrement iteration counter
                  → if iterations remain → go to WAITING_DELAY
                  → else → go to GROUP_DONE
WAITING_DELAY → (random delay expires) → go to SELECT_TARGET
GROUP_DONE → (all groups done?) → send FIN/ to app
```

Each group operates independently and in parallel. Multiple groups can have active targets simultaneously.

### 4.2 Program B — Individual Student Mode

Same state machine as Program A, but each target is its own "group" of one. A target activates, waits for completion, delays, and reactivates itself.

### 4.3 No-Shoot Target Behavior

- No-shoot targets are activated with `colorMode=2` but look identical to normal targets (same LED color).
- The LED only turns RED *after* a violation is detected.
- No-shoot targets deactivate on a timer (same random delay range), not on hit count.
- Violations are logged but the target remains active until its timer expires.

### 4.4 Late-Hit / Cooldown Behavior

After a target completes (required hits reached):
1. LED turns off.
2. Target enters COOLDOWN state for 2 seconds.
3. Any vibration during cooldown → LED flashes YELLOW → `EVT_LATE_HIT` sent.
4. After cooldown expires → target returns to IDLE.

### 4.5 STOP Handling

When transmitter receives `STOP/`:
1. Send `CMD_DEACTIVATE` to ALL targets in the current drill.
2. Reset all group state machines.
3. Send `FIN/` to app.
4. Return to idle, ready for next command.

---

## 5. Target Firmware State Machine

All targets run identical firmware (only `NODE_ADDRESS` differs).

```
IDLE (LED off, listening for commands)
│
├─ CMD_PING → send EVT_PONG → stay IDLE
├─ CMD_IDENTIFY → flash LED white 3x → stay IDLE
├─ CMD_ACTIVATE (colorMode=1) → LED on GREEN → go to ACTIVE_SHOOT
├─ CMD_ACTIVATE (colorMode=2) → LED on GREEN (identical) → go to ACTIVE_NOSHOOT
│
ACTIVE_SHOOT (LED green, counting hits)
│
├─ vibration detected → hitCount++
│   ├─ hitCount >= requiredHits → send EVT_COMPLETE → LED off → go to COOLDOWN
│   └─ hitCount < requiredHits → send EVT_HIT → stay ACTIVE_SHOOT
├─ CMD_DEACTIVATE → LED off → go to IDLE
│
ACTIVE_NOSHOOT (LED green, looks identical to shoot target)
│
├─ vibration detected → LED turns RED → send EVT_NOSHOOT_HIT → stay ACTIVE_NOSHOOT
├─ CMD_DEACTIVATE → LED off → go to IDLE
│
COOLDOWN (LED off, sensor active, 2-second window)
│
├─ vibration detected → LED flashes YELLOW → send EVT_LATE_HIT → stay COOLDOWN
├─ timer expires → go to IDLE
├─ CMD_ACTIVATE → go to ACTIVE_SHOOT or ACTIVE_NOSHOOT
├─ CMD_DEACTIVATE → go to IDLE
```

### Target Hardware Pin Mapping

| Component | Pin | Notes |
|-----------|-----|-------|
| NRF24L01 CE | 10 | |
| NRF24L01 CSN | 9 | |
| NRF24L01 SPI | 11 (MOSI), 12 (MISO), 13 (SCK) | Standard SPI |
| WS2812 LED strip | 5 | 6 LEDs, FastLED library |
| 12V relay | 2 | Controls external LED strip |
| Vibration sensor | A3 | `pulseIn(HIGH)` |

### LED Color Codes

| State | LED Color | When |
|-------|-----------|------|
| Active (shoot) | Green | Target awaiting hits |
| Active (no-shoot) | Green | Identical to shoot — deliberate |
| No-shoot violation | Red | After shooter hits a no-shoot target |
| Late hit | Yellow flash | Hit detected after deactivation |
| Identify | White flash 3x | App "find this target" feature |
| Idle / Off | Off | Not active |

---

## 6. Flutter App Architecture

### Directory Structure

```
lib/
├── main.dart
├── services/
│   ├── ble_service.dart              # BLE scan, connect, disconnect, reconnect
│   └── transmitter_protocol.dart     # Encode commands, decode telemetry
├── models/
│   ├── target_unit.dart              # id, address, group, isNoShoot, status
│   ├── target_group.dart             # id, name, list of target addresses
│   ├── drill_config.dart             # program type, timing, hits, groups, no-shoot list
│   ├── drill_session.dart            # runtime state: active drill, accumulated events
│   └── session_event.dart            # hit, violation, activation, completion events
├── screens/
│   ├── device_discovery_screen.dart  # BLE scan + connect to transmitter
│   ├── home_screen.dart              # Main menu (Program A, Program B)
│   ├── target_discovery_screen.dart  # NRF24 target scan, identify, group assignment
│   ├── program_a_setup_screen.dart   # Grouped mode config
│   ├── program_b_setup_screen.dart   # Individual mode config
│   ├── drill_running_screen.dart     # Timer + Stop button ONLY (no live stats)
│   └── results_screen.dart           # Post-drill: all telemetry, stats, export
├── widgets/
│   ├── inc_dec.dart                  # Numeric +/- input (reused from current app)
│   ├── target_chip.dart              # Small target indicator for group assignment
│   └── drill_timer.dart              # Elapsed time display
└── state/
    └── app_state.dart                # ChangeNotifier: connected device, discovered targets,
                                      #   current drill config, accumulated session events
```

### State Management

Provider + ChangeNotifier. Single `AppState` class that holds:
- Connected BLE device + characteristic reference
- List of discovered targets (from NRF24 scan)
- Current drill configuration
- Accumulated session events (populated silently during drill)
- Drill running flag + start timestamp

### Screen Flow

```
Device Discovery → Home Screen → Target Discovery → Program A/B Setup → Drill Running → Results
                                     ↑                                                      │
                                     └──────────────────────────────────────────────────────┘
```

### Drill Running Screen

Minimal by design:
- Large elapsed timer
- Stop button
- BLE notification listener accumulates events into `AppState.sessionEvents` silently
- On `FIN/` received or Stop pressed → navigate to Results screen

### Results Screen

Displays accumulated session data:
- Per-target summary: reaction time (activation → first hit), total hits, completion time
- No-shoot violations (which targets, count)
- Late-hit violations (which targets, count)
- Aggregate stats: average reaction time, total iterations completed
- Export to Excel (reuse Syncfusion dependency)

---

## 7. Reusable Code from Current App

| Component | Reuse? | Notes |
|-----------|--------|-------|
| BLE scan + connect flow (main.dart) | YES | Refactor into ble_service.dart |
| FFE0/FFE1 service discovery | YES | Correct UUIDs for HM-10 |
| chObj1.write(utf8.encode(...)) | YES | Correct write pattern |
| IncDec widget | YES | Rename to snake_case |
| ScanResultTile widget | YES | Simplify for production |
| ProgramA command format | PARTIAL | Field order changes, but slash-delimited pattern stays |
| ProgramB command format | PARTIAL | Same as above |
| STOP/ command | YES | Unchanged |
| Calculator screen | NO | Delete — legacy from brush pressure app |
| constants.dart | NO | Delete — only used by calculator |
| widgets.dart ServiceTile/CharacteristicTile/DescriptorTile | NO | Debug widgets, not needed |

---

## 8. Legacy Code Disposition

| File | Action |
|------|--------|
| calculator.dart | Delete |
| constants.dart | Delete |
| _showMeasureDialog() in main.dart | Delete |
| "Measure" button in main.dart | Delete |
| widgets.dart ServiceTile, CharacteristicTile, DescriptorTile | Delete |
| README.md | Rewrite |
| pubspec.yaml description | Update |

---

## 9. Open Questions

1. **Transmitter firmware source for the BLE-compatible version:** The v1.5 firmware uses interactive Serial prompts. The Flutter app sends A/B/STOP formatted strings. Either a newer firmware exists somewhere, or the transmitter firmware must be written fresh to parse the app's protocol. **Decision: Rewrite from scratch.**

2. **No-shoot deactivation timing:** Currently spec'd to use the same delay range as normal targets. Should no-shoot targets have a separate configurable on-time? (Can add later.)

3. **Vibration sensor calibration:** v1.5 firmware uses different thresholds per unit (0.2 vs 20). Need to standardize. Threshold may need to be configurable per-target or via a global setting.

4. **12V relay vs WS2812:** Some v1.5 units use the relay for LED control, others use WS2812 directly, some use both. Need to confirm which the current hardware uses. Firmware should support both (relay mirrors WS2812 state).

5. **BLE message fragmentation:** HM-10 modules typically have a 20-byte MTU. Longer messages (like Program A config with many targets) will need to be sent in chunks or the transmitter must reassemble. The transmitter should buffer incoming Serial bytes until it sees a terminating `/` with a complete command prefix.
