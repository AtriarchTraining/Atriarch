// firmware/transmitter/transmitter.ino
#include <SPI.h>
#include <RF24.h>
#include <RF24Network.h>
#include "config.h"
#include "serial_parser.h"

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
  bool noShoot[MAX_TARGETS_PER_GROUP];
  int activeTargetIdx;
  int activeTargetAddr;
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

// --- Forward declarations ---
void readSerial();
void handleNrfEvents();
void tickGroups();
void handleDiscovery();
void handleIdentify();
void handleProgramA();
void handleProgramB();
void handleStop();
void sendToTarget(int decimalId, int cmd, int param1, int param2);
float randomFloat(float minVal, float maxVal);
int octalToDecimalId(uint16_t octalAddr);
int getRequiredHitsForTarget(int decId);
bool isCommandComplete(const char* buf, char program);

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

// ============================================================
// Serial command reading and parsing
// ============================================================

void readSerial() {
  while (Serial.available()) {
    char c = Serial.read();

    if (serialPos >= SERIAL_BUF_SIZE - 1) {
      serialPos = 0;
      continue;
    }

    serialBuf[serialPos++] = c;
    serialBuf[serialPos] = '\0';

    if (c == '/' && serialPos >= 2) {
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
    }
  }
}

bool isCommandComplete(const char* buf, char program) {
  int slashes = 0;
  for (int i = 0; buf[i]; i++) {
    if (buf[i] == '/') slashes++;
  }
  if (program == 'A') return slashes >= 14;
  if (program == 'B') return slashes >= 10;
  return false;
}

// ============================================================
// NRF24 helpers
// ============================================================

void sendToTarget(int decimalId, int cmd, int param1, int param2) {
  if (decimalId < 1 || decimalId > MAX_TARGETS) return;
  uint16_t addr = addressMap[decimalId];
  int payload[MSG_SIZE] = {cmd, param1, param2};
  RF24NetworkHeader header(addr);
  network.write(header, &payload, sizeof(payload));
}

int octalToDecimalId(uint16_t octalAddr) {
  for (int i = 1; i <= MAX_TARGETS; i++) {
    if (addressMap[i] == octalAddr) return i;
  }
  return 0;
}

float randomFloat(float minVal, float maxVal) {
  return minVal + (float)random(0, 1000) / 1000.0 * (maxVal - minVal);
}

int getRequiredHitsForTarget(int decId) {
  for (int g = 0; g < activeGroupCount; g++) {
    if (groups[g].activeTargetAddr == decId) {
      return groups[g].requiredHits;
    }
  }
  return 0;
}

// ============================================================
// Discovery and Identify
// ============================================================

void handleDiscovery() {
  for (int id = 1; id <= MAX_TARGETS; id++) {
    sendToTarget(id, CMD_PING, 0, 0);

    unsigned long start = millis();
    while (millis() - start < 50) {
      network.update();
      if (network.available()) {
        RF24NetworkHeader header;
        int payload[MSG_SIZE] = {0, 0, 0};
        network.read(header, &payload, sizeof(payload));
        if (payload[0] == EVT_PONG) {
          // Report the actual responder's decimal ID from the RF24Network
          // header (header.from_node is the octal address of the sender).
          // Do NOT trust the loop variable `id` — a late/queued PONG from
          // an earlier PING could arrive during this window.
          int responderId = octalToDecimalId(header.from_node);
          if (responderId != 0) {
            Serial.print("D/");
            Serial.print(responderId);
            Serial.println("/");
          }
          break;
        }
      }
    }
  }
  Serial.println("DDONE/");
}

void handleIdentify() {
  char* p = serialBuf + 6; // skip "IDENT/"
  int addr = atoi(p);
  sendToTarget(addr, CMD_IDENTIFY, 0, 0);
}

// ============================================================
// Program A and B parsing
// ============================================================

void handleProgramA() {
  char* p = serialBuf + 2; // skip "A/"

  startMin = parseNextFloat(&p);
  startMax = parseNextFloat(&p);
  delayMin = parseNextFloat(&p);
  delayMax = parseNextFloat(&p);
  hitsMin = parseNextInt(&p);
  hitsMax = parseNextInt(&p);

  activeGroupCount = 0;
  for (int g = 0; g < 5; g++) {
    int targets[MAX_TARGETS_PER_GROUP];
    int count = parseNextIntList(&p, targets, MAX_TARGETS_PER_GROUP);

    if (count == 1 && targets[0] == 0) {
      groups[g].state = GRP_IDLE;
      groups[g].targetCount = 0;
      continue;
    }

    groups[g].targetCount = count;
    for (int i = 0; i < count; i++) {
      groups[g].targets[i] = targets[i];
      groups[g].noShoot[i] = false;
    }
    groups[g].state = GRP_WAITING_START;
    groups[g].iterationsLeft = 0;
    groups[g].timerStart = millis();
    groups[g].timerDuration = (unsigned long)(randomFloat(startMin, startMax) * 1000.0);
    activeGroupCount++;
  }

  // Parse no-shoot list
  noShootCount = parseNextIntList(&p, noShootTargets, MAX_TARGETS);

  // Mark no-shoot targets in groups
  for (int g = 0; g < 5; g++) {
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
  for (int g = 0; g < 5; g++) {
    if (groups[g].targetCount > 0) {
      groups[g].iterationsLeft = iterations;
    }
  }

  // Fix activeGroupCount to count actual active groups
  activeGroupCount = 0;
  for (int g = 0; g < 5; g++) {
    if (groups[g].targetCount > 0) activeGroupCount++;
  }

  drillRunning = true;
  Serial.println("Running Program A");
}

void handleProgramB() {
  char* p = serialBuf + 2; // skip "B/"

  startMin = parseNextFloat(&p);
  startMax = parseNextFloat(&p);
  delayMin = parseNextFloat(&p);
  delayMax = parseNextFloat(&p);
  hitsMin = parseNextInt(&p);
  hitsMax = parseNextInt(&p);

  int allTargets[MAX_TARGETS];
  int totalTargets = parseNextIntList(&p, allTargets, MAX_TARGETS);

  noShootCount = parseNextIntList(&p, noShootTargets, MAX_TARGETS);
  iterations = parseNextInt(&p);

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

// ============================================================
// Stop handler
// ============================================================

void handleStop() {
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

// ============================================================
// Group state machine tick
// ============================================================

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
        int idx = random(0, grp->targetCount);
        grp->activeTargetIdx = idx;
        grp->activeTargetAddr = grp->targets[idx];

        grp->requiredHits = random(hitsMin, hitsMax + 1);

        int colorMode = grp->noShoot[idx] ? COLOR_NOSHOOT : COLOR_NORMAL;

        sendToTarget(grp->activeTargetAddr, CMD_ACTIVATE, grp->requiredHits, colorMode);

        Serial.print("ACT/");
        Serial.print(grp->activeTargetAddr);
        Serial.println("/");

        grp->timerStart = now;
        grp->state = GRP_WAITING_COMPLETE;

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
        // For normal targets, completion handled in handleNrfEvents()
        break;

      case GRP_WAITING_DELAY:
        if (now - grp->timerStart >= grp->timerDuration) {
          grp->state = GRP_SELECT_TARGET;
        }
        break;
    }
  }

  if (doneCount == activeGroupCount && activeGroupCount > 0) {
    Serial.println("FIN/");
    drillRunning = false;
  }
}

// ============================================================
// NRF24 event handler (target telemetry relay)
// ============================================================

void handleNrfEvents() {
  while (network.available()) {
    RF24NetworkHeader header;
    int payload[MSG_SIZE] = {0, 0, 0};
    network.read(header, &payload, sizeof(payload));

    int decId = octalToDecimalId(header.from_node);
    if (decId == 0) continue;

    switch (payload[0]) {
      case EVT_PONG:
        // Handled inline during discovery scan
        break;

      case EVT_HIT:
        Serial.print("HIT/");
        Serial.print(decId);
        Serial.print("/");
        Serial.print(payload[1]);
        Serial.print("/");
        Serial.print(getRequiredHitsForTarget(decId));
        Serial.println("/");
        break;

      case EVT_COMPLETE: {
        Serial.print("DONE/");
        Serial.print(decId);
        Serial.print("/");
        Serial.print(payload[2]);
        Serial.println("/");

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
