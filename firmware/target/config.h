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
