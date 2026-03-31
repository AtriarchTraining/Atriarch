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
#define MAX_GROUPS      30  // Program B needs one group per target
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
