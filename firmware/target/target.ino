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
