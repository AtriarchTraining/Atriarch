// firmware/target/target.ino
#include <SPI.h>
#include <RF24.h>
#include <RF24Network.h>
#include <FastLED.h>
#include "config.h"

RF24 radio(NRF_CE_PIN, NRF_CSN_PIN);
RF24Network network(radio);

CRGB leds[NUM_LEDS];

// State
int state = STATE_IDLE;
int requiredHits = 0;
int hitCount = 0;
unsigned long activationTime = 0;
unsigned long cooldownStart = 0;
unsigned long lastVibTime = 0;
unsigned long identifyStart = 0;
int identifyFlashCount = 0;
bool identifyLedOn = false;

// Late-hit flash is non-blocking: armed when a hit lands during COOLDOWN,
// cleared in handleState() after LATE_HIT_FLASH_MS elapses. Loop budget
// must stay <=5ms per iteration so we cannot delay() here.
unsigned long lateHitFlashStart = 0;
bool lateHitFlashActive = false;

// Heartbeat / safe-stop watchdog state
unsigned long lastHeartbeatMs = 0;
unsigned long lastTxEventMs = 0;   // updated each time we send ANY event (coalescing)
unsigned long lastRxMs = 0;        // updated each time network.read() delivers a packet

void setup() {
  Serial.begin(9600);

  // NRF24
  SPI.begin();
  radio.begin();
  network.begin(RF24_CHANNEL, NODE_ADDRESS);
  radio.setDataRate(RF24_2MBPS);

  // LEDs
  FastLED.addLeds<WS2812, LED_STRIP_PIN, GRB>(leds, NUM_LEDS);
  fill_solid(leds, NUM_LEDS, CRGB::Black);
  FastLED.show();

  // Relay
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);

  // Vibration sensor
  // INPUT_PULLUP: SW-420 modules use an open-collector LM393 output —
  // nominally pulled HIGH by an on-module 10K resistor (idle) and pulled
  // LOW by the comparator on vibration. Enabling the ATmega's internal
  // ~30K pullup guarantees a stable HIGH idle state even if the module's
  // on-board pullup is weak, missing, or has a cold solder joint. This
  // inverts the polarity: hits are detected as LOW, not HIGH (see
  // checkVibration).
  pinMode(VIBRATION_PIN, INPUT_PULLUP);

  randomSeed(analogRead(0));

  // Initialize watchdog/heartbeat timestamps so a freshly-booted target
  // doesn't immediately trip the safe-stop watchdog or flood heartbeats.
  unsigned long now = millis();
  lastRxMs = now;
  lastHeartbeatMs = now;
  lastTxEventMs = now;

  Serial.print("Target node 0");
  Serial.print(NODE_ADDRESS, OCT);
  Serial.println(" ready.");
}

void loop() {
  network.update();
  handleIncoming();
  handleState();
  handleHeartbeat();
  handleSafeStop();
}

// ----- LED outputs split into two independent channels ---------------------
//
// Per Jeremy's spec (2026-04-21): the RELAY drives an external WHITE LED
// strip and is used to indicate a target is currently "active" (awaiting a
// shooter). The on-board WS2812 RGB strip is RESERVED for feedback signals
// only — no-shoot violations (red), late hits in cooldown (yellow), and
// identify flashes (white). A successful good hit does NOT flash the RGB;
// it just deactivates (relay off).

// Relay: drives the external 12V/5V white LED rail.
void setRelayOn()  { digitalWrite(RELAY_PIN, HIGH); }
void setRelayOff() { digitalWrite(RELAY_PIN, LOW);  }

// WS2812 RGB strip: feedback signals only.
void setRgbRed() {
  fill_solid(leds, NUM_LEDS, CRGB::Red);
  FastLED.show();
}
void setRgbYellow() {
  fill_solid(leds, NUM_LEDS, CRGB::Yellow);
  FastLED.show();
}
void setRgbWhite() {
  fill_solid(leds, NUM_LEDS, CRGB::White);
  FastLED.show();
}
void setRgbOff() {
  fill_solid(leds, NUM_LEDS, CRGB::Black);
  FastLED.show();
}

// Convenience for "fully deactivate" — relay off AND RGB off.
void allOff() {
  setRelayOff();
  setRgbOff();
}

// Hit detection via SW-420 vibration switch + LM393 comparator.
//
// VIBRATION_PIN uses internal ATmega pullup (pinMode INPUT_PULLUP in setup).
// Trigger polarity is configurable via VIB_TRIGGER_LEVEL in config.h because
// SW-420 modules ship with both polarities depending on manufacturer:
//   - Active-LOW  modules: D0 pulled HIGH at rest by onboard pullup, LM393
//                          sinks briefly on impact -> pin LOW == hit.
//   - Active-HIGH modules: D0 actively driven LOW at rest by LM393, released
//                          briefly on impact -> pin HIGH == hit.
// See config.h for how to identify which variant a physical unit has.
//
// VIB_DEBOUNCE_MS (100ms) keeps a single long pulse from being counted
// as multiple hits. Sensitivity is tuned by the trimmer pot on the
// SW-420 module, not firmware.
bool checkVibration() {
  if (digitalRead(VIBRATION_PIN) == VIB_TRIGGER_LEVEL) {
    unsigned long now = millis();
    if (now - lastVibTime > VIB_DEBOUNCE_MS) {
      lastVibTime = now;
      return true;
    }
  }
  return false;
}

// Non-ACK events use seq=0 in payload[3] per protocol spec.
// sendEvent() updates lastTxEventMs so the heartbeat emitter can coalesce.
void sendEvent(int eventType, int param1, int param2) {
  int payload[MSG_SIZE] = {eventType, param1, param2, 0};
  RF24NetworkHeader header(00);  // send to master node
  network.write(header, &payload, sizeof(payload));
  lastTxEventMs = millis();
}

// Send EVT_ACK echoing the cmdSeq of the received command. Dedicated helper
// because EVT_ACK is the only target->tx event that carries a non-zero seq.
void sendAck(int ackedCmdType, int cmdSeq) {
  int payload[MSG_SIZE] = {EVT_ACK, ackedCmdType, 0, cmdSeq};
  RF24NetworkHeader header(00);
  network.write(header, &payload, sizeof(payload));
  lastTxEventMs = millis();
}

// Periodic heartbeat emitter. Coalesced against any other TX event so we
// don't double-send right after a HIT/DONE/etc.
void handleHeartbeat() {
  unsigned long now = millis();
  if (now - lastTxEventMs < HEARTBEAT_INTERVAL_MS) return;
  if (now - lastHeartbeatMs < HEARTBEAT_INTERVAL_MS) return;
  int payload[MSG_SIZE] = {
    EVT_HB,
    (int)(now & 0xFFFF),
    (int)((now >> 16) & 0xFFFF),
    0
  };
  RF24NetworkHeader header(00);
  network.write(header, &payload, sizeof(payload));
  lastHeartbeatMs = now;
  lastTxEventMs = now;
}

// BLE safe-stop watchdog: if we haven't heard from the transmitter in
// BLE_SILENCE_TIMEOUT_MS and we're NOT already idle, drop to IDLE and
// kill LEDs/relay. No event is emitted — there's no master to hear it.
void handleSafeStop() {
  if (state == STATE_IDLE) return;
  unsigned long now = millis();
  if (now - lastRxMs > BLE_SILENCE_TIMEOUT_MS) {
    allOff();
    lateHitFlashActive = false;
    state = STATE_IDLE;
    // lastRxMs stays old until the next packet lands, which resets it.
  }
}

void handleIncoming() {
  while (network.available()) {
    RF24NetworkHeader header;
    int payload[MSG_SIZE] = {0, 0, 0, 0};
    network.read(header, &payload, sizeof(payload));

    // Any received packet resets both the BLE safe-stop watchdog and the
    // heartbeat reference — a recent RX is as good as a recent TX for the
    // purposes of proving the link is alive.
    lastRxMs = millis();

    int cmd = payload[0];
    int cmdSeq = payload[3];

    // EVT_ACK is emitted IMMEDIATELY, before acting on the command, so the
    // transmitter's journal sees the lowest-latency possible ACK. Only the
    // four ACK-tracked commands trigger this; unknown opcodes are ignored.
    switch (cmd) {
      case CMD_ACTIVATE:
      case CMD_DEACTIVATE:
      case CMD_IDENTIFY:
      case CMD_PING:
        sendAck(cmd, cmdSeq);
        break;
      default:
        // Unknown command — drop silently.
        continue;
    }

    // EVT_PONG on CMD_PING is retained alongside EVT_ACK because the
    // existing discovery flow looks for EVT_PONG specifically. The ACK is
    // additive and does not replace PONG for the discovery path.
    switch (cmd) {
      case CMD_PING:
        sendEvent(EVT_PONG, NODE_ADDRESS, 0);
        break;

      case CMD_IDENTIFY:
        state = STATE_IDENTIFYING;
        identifyStart = millis();
        identifyFlashCount = 0;
        identifyLedOn = false;
        break;

      case CMD_ACTIVATE:
        requiredHits = payload[1];
        hitCount = 0;
        activationTime = millis();
        if (payload[2] == COLOR_NOSHOOT) {
          state = STATE_ACTIVE_NOSHOOT;
        } else {
          state = STATE_ACTIVE_SHOOT;
        }
        lateHitFlashActive = false;  // clear any stale cooldown flash
        // Activation: turn on the white LED via relay. RGB stays off —
        // no-shoot targets are visually indistinguishable from shoot targets
        // during the active phase (deliberate per the design doc).
        setRelayOn();
        setRgbOff();
        break;

      case CMD_DEACTIVATE:
        state = STATE_IDLE;
        lateHitFlashActive = false;  // clear any stale cooldown flash
        allOff();
        break;
    }
  }
}

void handleState() {
  unsigned long now = millis();

  switch (state) {
    case STATE_IDLE:
      // Nothing to do — waiting for commands
      break;

    case STATE_ACTIVE_SHOOT:
      if (checkVibration()) {
        hitCount++;
        unsigned long elapsed = now - activationTime;
        if (hitCount >= requiredHits) {
          sendEvent(EVT_COMPLETE, hitCount, (int)(elapsed & 0x7FFF));
          // Good hit completing the iteration: just turn off. Per spec,
          // the RGB does NOT flash green — a clean deactivate is the
          // positive-feedback signal.
          allOff();
          cooldownStart = now;
          state = STATE_COOLDOWN;
        } else {
          sendEvent(EVT_HIT, hitCount, (int)(elapsed & 0x7FFF));
        }
      }
      break;

    case STATE_ACTIVE_NOSHOOT:
      if (checkVibration()) {
        unsigned long elapsed = now - activationTime;
        // No-shoot violation: RGB goes solid red. Relay stays ON — the
        // target remains active until the transmitter's timer fires a
        // CMD_DEACTIVATE. The red overlay is what signals "you hit a
        // no-shoot" to the shooter.
        setRgbRed();
        sendEvent(EVT_NOSHOOT_HIT, (int)(elapsed & 0x7FFF), 0);
      }
      break;

    case STATE_COOLDOWN:
      // Non-blocking late-hit flash: if armed and elapsed, clear the RGB
      // and the flag. Relay is already off from COMPLETE. Must run before
      // the vibration check so a fresh hit can re-arm on the same loop.
      if (lateHitFlashActive && (now - lateHitFlashStart >= LATE_HIT_FLASH_MS)) {
        setRgbOff();
        lateHitFlashActive = false;
      }

      if (now - cooldownStart >= COOLDOWN_MS) {
        // Cooldown over — return to IDLE. If a late-hit flash was still
        // active, clear it so we don't leak RGB state into IDLE.
        if (lateHitFlashActive) {
          setRgbOff();
          lateHitFlashActive = false;
        }
        state = STATE_IDLE;
      } else if (checkVibration()) {
        unsigned long elapsed = now - activationTime;
        // Late hit (vibration during cooldown): flash RGB yellow. Relay
        // stays off — the iteration is over, we're just signaling that
        // the shooter hit after the time expired.
        setRgbYellow();
        sendEvent(EVT_LATE_HIT, (int)(elapsed & 0x7FFF), 0);
        // Arm (or re-arm) the non-blocking flash timer. Replaces the
        // previous blocking delay(LATE_HIT_FLASH_MS) which violated the
        // <=5ms-per-iteration loop budget.
        lateHitFlashStart = now;
        lateHitFlashActive = true;
      }
      break;

    case STATE_IDENTIFYING:
      handleIdentify(now);
      break;
  }
}

void handleIdentify(unsigned long now) {
  // IDENTIFY uses ONLY the WS2812 RGB (white flash). The relay stays off
  // so this can't be confused with activation (which is the whole point
  // of identify — tell the trainer which target is which without arming
  // anything).
  unsigned long elapsed = now - identifyStart;
  int flashPhase = elapsed / IDENTIFY_FLASH_MS;

  if (flashPhase >= IDENTIFY_FLASHES * 2) {
    setRgbOff();
    state = STATE_IDLE;
    return;
  }

  bool shouldBeOn = (flashPhase % 2 == 0);
  if (shouldBeOn && !identifyLedOn) {
    setRgbWhite();
    identifyLedOn = true;
  } else if (!shouldBeOn && identifyLedOn) {
    setRgbOff();
    identifyLedOn = false;
  }
}
