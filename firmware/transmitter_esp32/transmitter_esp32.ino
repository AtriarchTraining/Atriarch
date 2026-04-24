// firmware/transmitter_esp32/transmitter_esp32.ino
//
// Atriarch Transmitter — ESP32-WROOM-32 port of firmware/transmitter/.
//
// This is a line-for-line port of the Nano sketch. The ONLY changes:
//   1. Pin map (NRF24 moved to VSPI on GPIO 18/19/21/22/23).
//   2. Transport layer (HM-10 SoftwareSerial -> native BLE via NimBLE).
//      - Protocol traffic in/out of the app now flows over the BleTransport.
//      - Native USB-serial is kept for DEBUG ONLY.
//   3. RF24 is constructed against a VSPI SPIClass and passed to radio.begin().
//
// All FSM, ACK journal, heartbeat tracker, STOP aggregate, and SNAP logic is
// preserved byte-for-byte from the Nano sketch per the engineering plan
// (§1.2, §1.3, §1.5 behavior contract).

#include <SPI.h>
#include <RF24.h>
#include <RF24Network.h>

#include "config.h"
#include "ble_transport.h"
#include "serial_parser.h"

// VSPI instance configured explicitly so the NRF24 doesn't share with the
// default HSPI that the ESP32 uses internally for flash.
SPIClass vspi(VSPI);

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

// --- Serial Buffer (protocol command assembly, fed from BLE rx queue) ---
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

// --- Pending-command journal (ACK retry) ---
// Indexed by decimal target ID 1..MAX_TARGETS. Slot 0 unused.
// Each target has at most ONE pending command at a time; a new send
// overwrites the previous slot (consistent with a simple command flow
// where the app never pipelines multiple outstanding CMD_* per target).
struct PendingCmd {
  int cmd;
  int param1;
  int param2;
  int seq;
  int retriesLeft;
  unsigned long nextRetryMs;
  bool ackReceived;
  bool inFlight;
};
PendingCmd pending[MAX_TARGETS + 1];
int nextCmdSeq = 1;  // rolls 1..255, never 0 (0 is reserved for "no-seq")

// --- Heartbeat tracker ---
// lastHbMs[i] is updated whenever we receive ANY event from target i
// (heartbeat coalescing: any event proves the target is alive).
unsigned long lastHbMs[MAX_TARGETS + 1];
int missedHbCount[MAX_TARGETS + 1];
bool targetOnline[MAX_TARGETS + 1];       // set true on first event / discovery PONG
bool targetUnreachable[MAX_TARGETS + 1];  // set true after UNREACHABLE_MISS_COUNT or ACK exhaust

// --- STOP aggregate tracking ---
bool stopInProgress = false;
unsigned long stopIssuedMs = 0;
bool stopAcked[MAX_TARGETS + 1];          // per-target STOP ACK received flag
bool stopAwaiting[MAX_TARGETS + 1];       // we issued CMD_DEACTIVATE to this target during STOP

// --- Active drill targets (for SNAP_REPLY) ---
// true from CMD_ACTIVATE -> EVT_COMPLETE / STOP for that target. Kept in
// sync by sendCmdWithAck (ACTIVATE) and the event/stop handlers.
bool drillActive[MAX_TARGETS + 1];

// --- Forward declarations ---
void readBle();
void handleNrfEvents();
void tickGroups();
void handleDiscovery();
void handleIdentify();
void handleProgramA();
void handleProgramB();
void handleStop();
void sendToTarget(int decimalId, int cmd, int param1, int param2);
void sendCmdWithAck(int decimalId, int cmd, int p1, int p2);
void sendRaw(int decimalId, int cmd, int p1, int p2, int seq);
int allocateCmdSeq();
void serviceAckRetries();
void serviceHeartbeatTracker();
void serviceStopAggregate();
void onAckReceived(int decimalId, int cmd);
void onAckFailed(int decimalId, int cmd);
void handleSnap();
void resetDrillState();
float randomFloat(float minVal, float maxVal);
int octalToDecimalId(uint16_t octalAddr);
int getRequiredHitsForTarget(int decId);
bool isCommandComplete(const char* buf, char program);

void setup() {
  // USB-serial for DEBUG ONLY. All protocol traffic goes over BLE.
  Serial.begin(115200);
  // Give the host USB-CDC enumeration a moment so the first prints aren't
  // swallowed during boot. 250 ms is generous and only happens at power-up.
  delay(250);
  Serial.println();
  Serial.println("=== Atriarch TX (ESP32) booting ===");

  // VSPI for NRF24. Default VSPI pins are 18/19/23/5 but we pin CSN to 21
  // (GPIO 5 is strapping + boot LED on many WROOM DevKits). Pass all four
  // pins explicitly so the mapping matches config.h and the wiring.
  vspi.begin(NRF_SCK_PIN, NRF_MISO_PIN, NRF_MOSI_PIN, NRF_CSN_PIN);

  bool rfBeginOk = radio.begin(&vspi);
  bool rfChipOk  = radio.isChipConnected();
  Serial.printf("[NRF24] radio.begin()=%s isChipConnected=%s\n",
                rfBeginOk ? "true" : "false",
                rfChipOk  ? "true" : "false");
  if (!rfBeginOk || !rfChipOk) {
    Serial.println("[NRF24] WARNING: radio not healthy — continuing anyway so BLE still comes up for diag");
  }

  network.begin(RF24_CHANNEL, MASTER_ADDRESS);
  radio.setDataRate(RF24_2MBPS);

  // ESP32 has a hardware RNG via esp_random(); Arduino's random() seeds from
  // analogRead(0) the same way as on Nano and works fine. Keep parity.
  randomSeed(analogRead(0));

  // Zero the ACK / heartbeat / drill tracking arrays. On ESP32 bss is
  // already zero-initialized at boot, but keep the explicit init so any
  // future drill reset calls have a single, obvious clearing path.
  for (int i = 0; i <= MAX_TARGETS; i++) {
    pending[i].inFlight = false;
    pending[i].ackReceived = false;
    lastHbMs[i] = 0;
    missedHbCount[i] = 0;
    targetOnline[i] = false;
    targetUnreachable[i] = false;
    stopAcked[i] = false;
    stopAwaiting[i] = false;
    drillActive[i] = false;
  }

  // Bring up BLE last so advertising starts only after NRF24 is ready.
  ble.begin();

  Serial.println("[boot] BLE advertising + NRF24 up");
  // Emit a ready banner over BLE too, but only once a central connects —
  // nothing will be notified until then, and the app doesn't expect a
  // banner anyway. (Nano's "Transmitter ready." line was on USB-serial for
  // developer diagnostics, not a protocol message.)
}

void loop() {
  network.update();
  readBle();
  handleNrfEvents();
  if (drillRunning) {
    tickGroups();
  }
  serviceAckRetries();
  serviceHeartbeatTracker();
  serviceStopAggregate();
}

// ============================================================
// BLE command reading and parsing
// ============================================================
//
// Mirrors the Nano readSerial() byte-by-byte. Only the byte source changes:
// Serial.read()/Serial.available() -> ble.read()/ble.available(). The buffer
// and the slash-terminated command-matching logic are identical.
void readBle() {
  while (ble.available()) {
    int b = ble.read();
    if (b < 0) break;
    char c = (char)b;

    if (serialPos >= SERIAL_BUF_SIZE - 1) {
      serialPos = 0;
      continue;
    }

    serialBuf[serialPos++] = c;
    serialBuf[serialPos] = '\0';

    if (c == '/' && serialPos >= 2) {
      if (strncmp(serialBuf, "DISC/", 5) == 0) {
        Serial.println("[CMD] DISC/ received");
        handleDiscovery();
        serialPos = 0;
      } else if (strncmp(serialBuf, "IDENT/", 6) == 0) {
        Serial.println("[CMD] IDENT/ received");
        handleIdentify();
        serialPos = 0;
      } else if (strncmp(serialBuf, "STOP/", 5) == 0) {
        Serial.println("[CMD] STOP/ received");
        handleStop();
        serialPos = 0;
      } else if (strncmp(serialBuf, "SNAP/", 5) == 0) {
        Serial.println("[CMD] SNAP/ received");
        handleSnap();
        serialPos = 0;
      } else if (serialBuf[0] == 'A' && serialBuf[1] == '/' && isCommandComplete(serialBuf, 'A')) {
        Serial.println("[CMD] Program A received");
        handleProgramA();
        serialPos = 0;
      } else if (serialBuf[0] == 'B' && serialBuf[1] == '/' && isCommandComplete(serialBuf, 'B')) {
        Serial.println("[CMD] Program B received");
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

// Fire-and-forget send used for PING scans during discovery. A seq of 0
// would be interpreted as "no-seq" by the target's ACK logic, but the
// target still echoes EVT_ACK with seq=0 which the journal ignores
// because no pending[] slot has seq=0. For PING we use a fresh seq so the
// target's EVT_ACK is harmless; EVT_PONG is what discovery actually watches.
void sendToTarget(int decimalId, int cmd, int param1, int param2) {
  if (decimalId < 1 || decimalId > MAX_TARGETS) return;
  int seq = allocateCmdSeq();
  sendRaw(decimalId, cmd, param1, param2, seq);
}

// Allocate the next cmdSeq in the rolling 1..255 space (0 reserved).
int allocateCmdSeq() {
  int s = nextCmdSeq++;
  if (nextCmdSeq > 255) nextCmdSeq = 1;
  return s;
}

// Raw RF24 send — no journal bookkeeping. Used by both sendCmdWithAck()
// (initial send + retries) and by the discovery PING scan.
void sendRaw(int decimalId, int cmd, int p1, int p2, int seq) {
  if (decimalId < 1 || decimalId > MAX_TARGETS) return;
  uint16_t addr = addressMap[decimalId];
  // CRITICAL: target firmware runs on ATmega328P where `int` is 16-bit.
  // ESP32's `int` is 32-bit, so using `int payload[]` here sends 16 bytes
  // instead of 8 and every value gets misinterpreted by the target. Use
  // int16_t to match the AVR wire format exactly.
  int16_t payload[MSG_SIZE] = {(int16_t)cmd, (int16_t)p1, (int16_t)p2, (int16_t)seq};
  RF24NetworkHeader header(addr);
  network.write(header, &payload, sizeof(payload));
}

// Record a pending command in the journal and transmit the first attempt.
// Overwrites any previous in-flight entry for this target (see note on
// pipelining in the PendingCmd struct declaration).
void sendCmdWithAck(int decimalId, int cmd, int p1, int p2) {
  if (decimalId < 1 || decimalId > MAX_TARGETS) return;
  int seq = allocateCmdSeq();
  pending[decimalId].cmd = cmd;
  pending[decimalId].param1 = p1;
  pending[decimalId].param2 = p2;
  pending[decimalId].seq = seq;
  pending[decimalId].retriesLeft = ACK_MAX_RETRIES;
  pending[decimalId].nextRetryMs = millis() + ACK_TIMEOUT_MS;
  pending[decimalId].ackReceived = false;
  pending[decimalId].inFlight = true;
  sendRaw(decimalId, cmd, p1, p2, seq);
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
  Serial.println("[DISC] scan start — pinging 30 addresses");
  int found = 0;
  for (int id = 1; id <= MAX_TARGETS; id++) {
    sendToTarget(id, CMD_PING, 0, 0);

    unsigned long start = millis();
    while (millis() - start < 50) {
      network.update();
      if (network.available()) {
        RF24NetworkHeader header;
        int16_t payload[MSG_SIZE] = {0, 0, 0, 0};
        network.read(header, &payload, sizeof(payload));

        // A target that is awake will emit EVT_ACK (seq-correlated) AND
        // EVT_PONG for a PING. We treat either as proof of life but only
        // report on EVT_PONG to preserve the existing discovery contract.
        // EVT_ACK and EVT_HB also prime targetOnline / lastHbMs so the
        // heartbeat tracker doesn't flag the target as unreachable later.
        int responderId = octalToDecimalId(header.from_node);
        Serial.printf("[DISC] rx from_node=0%o evt=%d responderId=%d\n",
                      header.from_node, (int)payload[0], responderId);
        if (responderId != 0 &&
            (payload[0] == EVT_PONG || payload[0] == EVT_ACK || payload[0] == EVT_HB)) {
          lastHbMs[responderId] = millis();
          missedHbCount[responderId] = 0;
          targetOnline[responderId] = true;
          targetUnreachable[responderId] = false;
        }

        if (payload[0] == EVT_PONG) {
          if (responderId != 0) {
            Serial.printf("[DISC] PONG from T%d -> emit D/%d/\n", responderId, responderId);
            ble.printf("D/%d/\n", responderId);
            found++;
          }
          break;
        }
      }
    }
  }
  Serial.printf("[DISC] scan complete — %d target(s) responded, emitting DDONE/\n", found);
  ble.println("DDONE/");
}

void handleIdentify() {
  char* p = serialBuf + 6; // skip "IDENT/"
  int addr = atoi(p);
  // IDENTIFY is ACK-tracked per spec but treated fire-and-forget at the
  // app level (onAckReceived is a no-op for CMD_IDENTIFY). Running it
  // through the journal still gives us retries over a flaky link.
  sendCmdWithAck(addr, CMD_IDENTIFY, 0, 0);
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
  Serial.println("[drill] Running Program A");
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
  Serial.println("[drill] Running Program B");
}

// ============================================================
// Stop handler
// ============================================================

void handleStop() {
  // Begin the aggregate STOP flow: issue CMD_DEACTIVATE (ACK-tracked) to
  // every target we believe is currently active. STOP_ACK is emitted to
  // the app only after every awaited target has ACKed (or been marked
  // unreachable / timed out via STOP_AGGREGATE_TIMEOUT_MS).
  stopInProgress = true;
  stopIssuedMs = millis();

  // Reset stop tracking arrays.
  for (int i = 0; i <= MAX_TARGETS; i++) {
    stopAcked[i] = false;
    stopAwaiting[i] = false;
  }

  for (int g = 0; g < activeGroupCount; g++) {
    if (groups[g].state == GRP_WAITING_COMPLETE) {
      int id = groups[g].activeTargetAddr;
      if (id >= 1 && id <= MAX_TARGETS) {
        stopAwaiting[id] = true;
        sendCmdWithAck(id, CMD_DEACTIVATE, 0, 0);
      }
    }
    // Tear down group state immediately so tickGroups stops advancing.
    groups[g].state = GRP_IDLE;
    groups[g].targetCount = 0;
  }

  activeGroupCount = 0;
  drillRunning = false;

  // Preserve legacy "FIN/" emission for backwards compatibility with the
  // existing app parser; STOP_ACK/ is the new, per-spec confirmation that
  // the transmitter is satisfied all targets have stopped.
  ble.println("FIN/");

  // If nothing was awaiting STOP (e.g. STOP pressed before any activation),
  // emit STOP_ACK immediately via the aggregate service on next tick.
}

// Clear drill-scoped state after STOP completes. Does NOT touch targetOnline
// or the heartbeat tracker — those remain valid across drills.
void resetDrillState() {
  for (int i = 0; i <= MAX_TARGETS; i++) {
    drillActive[i] = false;
    stopAwaiting[i] = false;
    stopAcked[i] = false;
    // Clear any still-pending commands; the drill is over and the ACK
    // journal should not keep retrying old ACTIVATEs/DEACTIVATEs.
    pending[i].inFlight = false;
    pending[i].ackReceived = false;
  }
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

        // Skip unreachable targets for this iteration. The target stays in
        // the group pool; we just don't bother activating it this round.
        // TODO(v2): fancier rotation if all targets in a group go dark —
        // for now, keep tick cadence and let the FSM retry next iteration.
        if (grp->activeTargetAddr >= 1 && grp->activeTargetAddr <= MAX_TARGETS &&
            targetUnreachable[grp->activeTargetAddr]) {
          // Advance as if the iteration completed so the drill keeps moving.
          grp->iterationsLeft--;
          if (grp->iterationsLeft <= 0 && iterations > 0) {
            grp->state = GRP_DONE;
          } else {
            grp->timerStart = now;
            grp->timerDuration = (unsigned long)(randomFloat(delayMin, delayMax) * 1000.0);
            grp->state = GRP_WAITING_DELAY;
          }
          break;
        }

        grp->requiredHits = random(hitsMin, hitsMax + 1);

        int colorMode = grp->noShoot[idx] ? COLOR_NOSHOOT : COLOR_NORMAL;

        // Send CMD_ACTIVATE through the ACK journal. "ACT/" is NOT emitted
        // here — per the eng plan it's emitted only after the target ACKs
        // the activation (see onAckReceived).
        Serial.printf("[TX] sending CMD_ACTIVATE to T%d hits=%d color=%d\n",
                      grp->activeTargetAddr, grp->requiredHits, colorMode);
        sendCmdWithAck(grp->activeTargetAddr, CMD_ACTIVATE, grp->requiredHits, colorMode);
        drillActive[grp->activeTargetAddr] = true;

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
            sendCmdWithAck(grp->activeTargetAddr, CMD_DEACTIVATE, 0, 0);
            drillActive[grp->activeTargetAddr] = false;
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
    ble.println("FIN/");
    drillRunning = false;
  }
}

// ============================================================
// NRF24 event handler (target telemetry relay)
// ============================================================

void handleNrfEvents() {
  while (network.available()) {
    RF24NetworkHeader header;
    // int16_t to match target AVR's 16-bit int wire format.
    int16_t payload[MSG_SIZE] = {0, 0, 0, 0};
    network.read(header, &payload, sizeof(payload));

    int decId = octalToDecimalId(header.from_node);
    if (decId == 0) continue;

    // ANY event from a target resets the heartbeat tracker — coalescing
    // applies at the transmitter side too. Also clears the unreachable
    // flag because the target has proven itself alive again.
    lastHbMs[decId] = millis();
    missedHbCount[decId] = 0;
    targetOnline[decId] = true;
    targetUnreachable[decId] = false;

    switch (payload[0]) {
      case EVT_ACK: {
        // payload[1] = acked command type, payload[3] = cmdSeq
        int ackedCmd = payload[1];
        int ackedSeq = payload[3];
        if (pending[decId].inFlight && pending[decId].seq == ackedSeq) {
          pending[decId].ackReceived = true;
          pending[decId].inFlight = false;
          onAckReceived(decId, ackedCmd);
        }
        // else: stale ACK (e.g. for a cancelled/overwritten command). Drop.
        break;
      }

      case EVT_HB:
        // Heartbeat — tracker already updated above. Nothing else to do.
        break;

      case EVT_PONG:
        // Handled inline during discovery scan
        break;

      case EVT_HIT:
        Serial.printf("[HIT] T%d hit %d of %d\n", decId, (int)payload[1], getRequiredHitsForTarget(decId));
        ble.printf("HIT/%d/%d/%d/\n", decId, payload[1], getRequiredHitsForTarget(decId));
        break;

      case EVT_COMPLETE: {
        Serial.printf("[DONE] T%d complete in %dms\n", decId, (int)payload[2]);
        ble.printf("DONE/%d/%d/\n", decId, payload[2]);

        // Target reported completion — no longer active in the drill.
        drillActive[decId] = false;

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
        Serial.printf("[NS] T%d no-shoot violation\n", decId);
        ble.printf("NS/%d/\n", decId);
        break;

      case EVT_LATE_HIT:
        Serial.printf("[LATE] T%d late hit\n", decId);
        ble.printf("LATE/%d/\n", decId);
        break;
    }
  }
}

// ============================================================
// ACK retry service
// ============================================================

// Iterate the pending journal. For any entry whose retry timer has fired,
// either resend (retriesLeft > 0) or fail out the command (retriesLeft <= 0).
// Non-blocking; one full pass per loop iteration.
void serviceAckRetries() {
  unsigned long now = millis();
  for (int i = 1; i <= MAX_TARGETS; i++) {
    if (!pending[i].inFlight) continue;
    if (pending[i].ackReceived) continue;
    if ((long)(now - pending[i].nextRetryMs) < 0) continue;
    if (pending[i].retriesLeft <= 0) {
      int failedCmd = pending[i].cmd;
      pending[i].inFlight = false;
      onAckFailed(i, failedCmd);
      continue;
    }
    pending[i].retriesLeft--;
    pending[i].nextRetryMs = now + ACK_TIMEOUT_MS;
    sendRaw(i, pending[i].cmd, pending[i].param1, pending[i].param2, pending[i].seq);
  }
}

// Called when an EVT_ACK matches a pending journal entry.
// Per eng plan: ACT/ is emitted only after target ACKs CMD_ACTIVATE.
// CMD_DEACTIVATE contributes to the STOP aggregate. PING/IDENTIFY are no-op.
void onAckReceived(int decimalId, int cmd) {
  switch (cmd) {
    case CMD_ACTIVATE:
      Serial.printf("[ACT] T%d activated (CMD_ACTIVATE ACKed)\n", decimalId);
      ble.printf("ACT/%d/\n", decimalId);
      break;
    case CMD_DEACTIVATE:
      if (decimalId >= 1 && decimalId <= MAX_TARGETS) {
        stopAcked[decimalId] = true;
      }
      break;
    case CMD_PING:
    case CMD_IDENTIFY:
    default:
      // Fire-and-forget at the app level — nothing to do.
      break;
  }
}

// Called when retriesLeft is exhausted for a pending command.
// During a live drill, emits ERR/unreachable/ and marks the target so the
// FSM skips it next iteration. During STOP, treats the target as
// "accounted for" so the aggregate STOP_ACK can still complete.
void onAckFailed(int decimalId, int cmd) {
  if (decimalId < 1 || decimalId > MAX_TARGETS) return;

  Serial.printf("[ACK-FAIL] T%d cmd=%d (retries exhausted, marked unreachable)\n", decimalId, cmd);
  targetUnreachable[decimalId] = true;

  if (cmd == CMD_DEACTIVATE) {
    // During STOP: mark as answered so aggregate STOP_ACK doesn't hang.
    // Target's own 5s BLE watchdog is the physical fail-safe.
    stopAcked[decimalId] = true;
    // If STOP isn't in progress, this was a mid-drill no-shoot deactivate
    // or similar; still treat the target as unreachable for the drill.
    if (drillRunning && !stopInProgress) {
      ble.printf("ERR/unreachable/%d/\n", decimalId);
    }
    return;
  }

  // CMD_ACTIVATE / CMD_PING / CMD_IDENTIFY failures: emit unreachable if
  // we're in a live drill. Outside a drill, failed PING/IDENTIFY are
  // benign — no ERR emission (avoids spamming the app during discovery).
  if (drillRunning) {
    ble.printf("ERR/unreachable/%d/\n", decimalId);
  }
}

// ============================================================
// Heartbeat tracker service
// ============================================================

// For each known-online target, escalate missedHbCount when the expected
// heartbeat window lapses. At UNREACHABLE_MISS_COUNT misses, flag the
// target unreachable and (if a drill is running) notify the app.
void serviceHeartbeatTracker() {
  unsigned long now = millis();
  for (int i = 1; i <= MAX_TARGETS; i++) {
    if (!targetOnline[i]) continue;
    if (targetUnreachable[i]) continue;  // already reported
    unsigned long window = (unsigned long)HEARTBEAT_INTERVAL_MS * (missedHbCount[i] + 1);
    if (now - lastHbMs[i] >= window) {
      missedHbCount[i]++;
      if (missedHbCount[i] >= UNREACHABLE_MISS_COUNT) {
        targetUnreachable[i] = true;
        // Post-drill unreachable is benign until the next drill starts —
        // don't spam the app outside a drill.
        if (drillRunning) {
          ble.printf("ERR/unreachable/%d/\n", i);
        }
      }
    }
  }
}

// ============================================================
// STOP aggregate service
// ============================================================

// Emit STOP_ACK/ once every awaited CMD_DEACTIVATE has been ACKed OR the
// aggregate timeout fires. Cleans up drill-scoped state afterwards.
void serviceStopAggregate() {
  if (!stopInProgress) return;
  unsigned long now = millis();

  bool allDone = true;
  for (int i = 1; i <= MAX_TARGETS; i++) {
    if (!stopAwaiting[i]) continue;
    if (stopAcked[i]) continue;
    if (targetUnreachable[i]) continue;  // give up on this one
    allDone = false;
    break;
  }

  if (allDone || (now - stopIssuedMs > STOP_AGGREGATE_TIMEOUT_MS)) {
    ble.println("STOP_ACK/");
    stopInProgress = false;
    resetDrillState();
  }
}

// ============================================================
// SNAP handler — state snapshot for app reconnect
// ============================================================

// Emit SNAP_REPLY/<running>/<activeIds>/ where activeIds is a comma-
// separated list of drill-active target decimal IDs, or "0" if empty.
// Active = "was issued CMD_ACTIVATE and hasn't yet emitted EVT_COMPLETE
// or been stopped" — tracked via the drillActive[] flag.
void handleSnap() {
  // Build the list into a local buffer so the whole SNAP_REPLY fits in one
  // logical BLE frame (or at most two 20-byte chunks). The Nano version
  // could dribble bytes one-Serial.print-at-a-time because USB-serial was
  // a stream; BLE notifications are per-packet. Worst case: "SNAP_REPLY/
  // 1/1,2,3,...,30/\n" ~70 bytes, well within the ring-buffer assembly on
  // the app side.
  char line[96];
  int n = snprintf(line, sizeof(line), "SNAP_REPLY/%d/", drillRunning ? 1 : 0);

  bool any = false;
  for (int i = 1; i <= MAX_TARGETS && n < (int)sizeof(line) - 8; i++) {
    if (!drillActive[i]) continue;
    n += snprintf(line + n, sizeof(line) - n, "%s%d", any ? "," : "", i);
    any = true;
  }
  if (!any) {
    n += snprintf(line + n, sizeof(line) - n, "0");
  }
  n += snprintf(line + n, sizeof(line) - n, "/\n");

  if (n > 0) {
    ble.write(reinterpret_cast<const uint8_t*>(line),
              (size_t)((n < (int)sizeof(line)) ? n : (int)sizeof(line) - 1));
  }
}
