// firmware/target_vib_debug/target_vib_debug.ino
//
// Multi-pin scanner: identifies which analog pin (A0..A5) the SW-420 D0
// signal is actually reaching. Keep the sensor wired where it is.
// Shake the target and read which LED flashes red:
//
//   LED[0] = A0   LED[3] = A3
//   LED[1] = A1   LED[4] = A4
//   LED[2] = A2   LED[5] = A5
//
// Multiple LEDs flashing = signal bleeds onto multiple pins (unlikely).
// No LEDs flashing      = signal is not on any analog pin; widen search
//                         to D3/D4/D6/D7/D8.

#include <FastLED.h>

#define LED_STRIP_PIN 5
#define NUM_LEDS 6
#define RELAY_PIN 2
#define FLASH_MS 200

CRGB leds[NUM_LEDS];
const uint8_t pins[NUM_LEDS] = { A0, A1, A2, A3, A4, A5 };
unsigned long flashUntil[NUM_LEDS] = { 0, 0, 0, 0, 0, 0 };

void setup() {
  for (int i = 0; i < NUM_LEDS; i++) {
    pinMode(pins[i], INPUT_PULLUP);
  }
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);

  FastLED.addLeds<WS2812B, LED_STRIP_PIN, GRB>(leds, NUM_LEDS);
  FastLED.setBrightness(80);

  // Boot: green sweep L->R so LED ordering is obvious
  for (int i = 0; i < NUM_LEDS; i++) {
    fill_solid(leds, NUM_LEDS, CRGB::Black);
    leds[i] = CRGB::Green;
    FastLED.show();
    delay(100);
  }
  fill_solid(leds, NUM_LEDS, CRGB::Black);
  FastLED.show();
}

void loop() {
  unsigned long now = millis();
  for (int i = 0; i < NUM_LEDS; i++) {
    if (digitalRead(pins[i]) == LOW) {
      flashUntil[i] = now + FLASH_MS;
    }
    leds[i] = (now < flashUntil[i]) ? CRGB::Red : CRGB::Black;
  }
  FastLED.show();
}
