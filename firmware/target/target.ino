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

  Serial.print("Target node 0");
  Serial.print(NODE_ADDRESS, OCT);
  Serial.println(" ready.");
}

void loop() {
  network.update();
  handleIncoming();
  handleState();
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

void sendEvent(int eventType, int param1, int param2) {
  int payload[MSG_SIZE] = {eventType, param1, param2};
  RF24NetworkHeader header(00);  // send to master node
  network.write(header, &payload, sizeof(payload));
}

void handleIncoming() {
  while (network.available()) {
    RF24NetworkHeader header;
    int payload[MSG_SIZE] = {0, 0, 0};
    network.read(header, &payload, sizeof(payload));

    int cmd = payload[0];

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
        setLedGreen();
        break;

      case CMD_DEACTIVATE:
        state = STATE_IDLE;
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
      if (now - cooldownStart >= COOLDOWN_MS) {
        state = STATE_IDLE;
      } else if (checkVibration()) {
        unsigned long elapsed = now - activationTime;
        setLedYellow();
        sendEvent(EVT_LATE_HIT, (int)(elapsed & 0x7FFF), 0);
        delay(LATE_HIT_FLASH_MS);
        setLedOff();
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
