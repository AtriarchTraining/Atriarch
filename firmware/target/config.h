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
#define NODE_ADDRESS    02  // <-- CHANGE THIS PER TARGET

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
#define EVT_ACK         15   // target ACKs a received command
#define EVT_HB          16   // heartbeat (periodic)

// --- Heartbeat timing ---
#define HEARTBEAT_INTERVAL_MS   1500
#define UNREACHABLE_MISS_COUNT  3
#define UNREACHABLE_WINDOW_MS   4500

// --- ACK retry ---
#define ACK_TIMEOUT_MS          300
#define ACK_MAX_RETRIES         3

// --- BLE safe-stop watchdog (target) ---
// 60s is the Gate 1 pragmatic setting: long enough that slow drills don't
// trip the watchdog mid-wait, short enough that a truly-dead transmitter
// still safe-stops the fleet within a minute. The eng plan §1.2 proposed
// 5000ms but that fires during normal wait-for-hit on Program B drills.
// v2 proper fix: have the transmitter send a 2-second keepalive CMD_PING
// to any target currently in ACTIVE_* state, then this can drop back to 5s.
#define BLE_SILENCE_TIMEOUT_MS  60000

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
#define VIB_THRESHOLD       20  // pulseIn microseconds; legacy, unused by digitalRead detection

// SW-420 modules ship with two output polarities. To figure out which one
// your module is, observe the DO-LED on the sensor module at rest and on tap:
//   - DO-LED OFF at rest, briefly ON when you tap  ->  set to LOW  (D0 is
//       active-LOW on trigger — comparator sinks current only during impact)
//   - DO-LED ON  at rest, briefly OFF when you tap ->  set to HIGH (D0 is
//       active-HIGH on trigger — comparator sinks at rest, releases on impact)
//
// Jeremy's 2026-04-21 batch is the HIGH variant. If you install a different
// module and hits stop registering OR targets self-trigger at rest, flip this.
#define VIB_TRIGGER_LEVEL   HIGH

// --- NRF24 Message Size ---
// BREAKING: bumped from 3 to 4. payload[3] = cmdSeq for ACK correlation.
#define MSG_SIZE 4  // max ints in a command/event payload

#endif
