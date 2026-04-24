// firmware/transmitter_esp32/config.h
//
// ESP32-WROOM-32 transmitter config. Ported from firmware/transmitter/config.h
// (Nano version). The ONLY differences are the pin map (NRF24 on VSPI) and
// the BLE section (HM-10 serial replaced with native ESP32 BLE peripheral).
// All protocol constants are IDENTICAL to the Nano config so the target-side
// firmware, the app-side parser, and the on-air NRF24 frames stay the same.

#ifndef CONFIG_H
#define CONFIG_H

// --- Pin Definitions (ESP32-WROOM-32 DevKit, VSPI) ---
#define NRF_CE_PIN      22
#define NRF_CSN_PIN     21
#define NRF_SCK_PIN     18   // VSPI default SCK
#define NRF_MOSI_PIN    23   // VSPI default MOSI
#define NRF_MISO_PIN    19   // VSPI default MISO
// NRF24 IRQ pin is unconnected; RF24Network polls.

// --- BLE peripheral settings (native ESP32 BLE via NimBLE) ---
// UUIDs deliberately MATCH the HM-10 module's default service/characteristic
// so the Flutter app requires zero UUID-level changes.
#define BLE_DEVICE_NAME       "Atriarch-TX"
#define BLE_SERVICE_UUID      "0000ffe0-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_UUID         "0000ffe1-0000-1000-8000-00805f9b34fb"

// Inbound ring buffer for bytes received over the NimBLE write characteristic.
// Longest practical app command is Program A with full groups / no-shoot list,
// ~200 chars; 512 gives generous slack.
#define BLE_RX_BUF_SIZE       512

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
#define BLE_SILENCE_TIMEOUT_MS  5000

// --- STOP aggregate timeout ---
#define STOP_AGGREGATE_TIMEOUT_MS  5000  // if not all STOP_ACKs by then, emit STOP_ACK anyway

// --- Color Modes ---
#define COLOR_NORMAL    1
#define COLOR_NOSHOOT   2

// --- Limits ---
#define MAX_TARGETS     30
#define MAX_GROUPS      30  // Program B needs one group per target
#define MAX_TARGETS_PER_GROUP 10
#define SERIAL_BUF_SIZE 256  // reused as the parser's command buffer size

// --- NRF24 Message Size ---
// BREAKING: bumped from 3 to 4. payload[3] = cmdSeq for ACK correlation.
#define MSG_SIZE 4

// --- Group States ---
#define GRP_IDLE            0
#define GRP_WAITING_START   1
#define GRP_SELECT_TARGET   2
#define GRP_WAITING_COMPLETE 3
#define GRP_WAITING_DELAY   4
#define GRP_DONE            5

#endif
