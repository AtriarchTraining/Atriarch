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
  pinMode(VIBRATION_PIN, INPUT);

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

void setLedGreen() {
  fill_solid(leds, NUM_LEDS, CRGB::Green);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedRed() {
  fill_solid(leds, NUM_LEDS, CRGB::Red);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedYellow() {
  fill_solid(leds, NUM_LEDS, CRGB::Yellow);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedWhite() {
  fill_solid(leds, NUM_LEDS, CRGB::White);
  FastLED.show();
  digitalWrite(RELAY_PIN, HIGH);
}

void setLedOff() {
  fill_solid(leds, NUM_LEDS, CRGB::Black);
  FastLED.show();
  digitalWrite(RELAY_PIN, LOW);
}

bool checkVibration() {
  long measurement = pulseIn(VIBRATION_PIN, HIGH, 1000); // 1ms timeout
  if (measurement > VIB_THRESHOLD) {
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
    setLedOff();
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
        setLedGreen();
        break;

      case CMD_DEACTIVATE:
        state = STATE_IDLE;
        lateHitFlashActive = false;  // clear any stale cooldown flash
        setLedOff();
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
          setLedOff();
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
        setLedRed();
        sendEvent(EVT_NOSHOOT_HIT, (int)(elapsed & 0x7FFF), 0);
      }
      break;

    case STATE_COOLDOWN:
      // Non-blocking late-hit flash: if armed and elapsed, turn LED off
      // and clear the flag. Must run before the vibration check so a
      // fresh hit can re-arm the flash on the same loop iteration.
      if (lateHitFlashActive && (now - lateHitFlashStart >= LATE_HIT_FLASH_MS)) {
        setLedOff();
        lateHitFlashActive = false;
      }

      if (now - cooldownStart >= COOLDOWN_MS) {
        // Cooldown over — return to IDLE. If a late-hit flash was still
        // active, clear it so we don't leak LED state into IDLE.
        if (lateHitFlashActive) {
          setLedOff();
          lateHitFlashActive = false;
        }
        state = STATE_IDLE;
      } else if (checkVibration()) {
        unsigned long elapsed = now - activationTime;
        setLedYellow();
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
  unsigned long elapsed = now - identifyStart;
  int flashPhase = elapsed / IDENTIFY_FLASH_MS;

  if (flashPhase >= IDENTIFY_FLASHES * 2) {
    setLedOff();
    state = STATE_IDLE;
    return;
  }

  bool shouldBeOn = (flashPhase % 2 == 0);
  if (shouldBeOn && !identifyLedOn) {
    setLedWhite();
    identifyLedOn = true;
  } else if (!shouldBeOn && identifyLedOn) {
    setLedOff();
    identifyLedOn = false;
  }
}
