// NRF24 wiring verification — Atriarch ESP32 port, Phase 2.5
// Probes the NRF24L01 over SPI. Signals result via onboard LED:
//   FAST blink (100ms on / 100ms off) = NRF24 responds = wiring OK
//   SLOW blink (1s on / 1s off)       = NRF24 does NOT respond = wiring issue
// Also prints detail over Serial at 115200 baud.

#include <SPI.h>
#include <RF24.h>

// ESP32 pinout per Atriarch port plan (lib/theme/... no, docs/superpowers/plans/2026-04-20-esp32-transmitter-port.md)
#define NRF_CE_PIN    22
#define NRF_CSN_PIN   21
#define NRF_SCK_PIN   18
#define NRF_MOSI_PIN  23
#define NRF_MISO_PIN  19

#define LED_PIN       2

SPIClass vspi(VSPI);
RF24 radio(NRF_CE_PIN, NRF_CSN_PIN);

bool wiringOk = false;

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  delay(500);

  Serial.println();
  Serial.println(F("=== NRF24 Wiring Probe — Atriarch ==="));
  Serial.printf("Pins: CE=%d CSN=%d SCK=%d MOSI=%d MISO=%d\n",
                NRF_CE_PIN, NRF_CSN_PIN, NRF_SCK_PIN, NRF_MOSI_PIN, NRF_MISO_PIN);

  vspi.begin(NRF_SCK_PIN, NRF_MISO_PIN, NRF_MOSI_PIN, NRF_CSN_PIN);
  Serial.println(F("VSPI started."));

  bool begun = radio.begin(&vspi);
  Serial.printf("radio.begin(): %s\n", begun ? "OK" : "FAIL");

  bool connected = radio.isChipConnected();
  Serial.printf("radio.isChipConnected(): %s\n", connected ? "YES" : "NO");

  if (begun && connected) {
    wiringOk = true;
    Serial.println();
    Serial.println(F("Radio register dump (proves SPI bidirectional):"));
    radio.printPrettyDetails();
    Serial.println();
    Serial.println(F("+---------------------------------------+"));
    Serial.println(F("| WIRING OK — NRF24 responds over SPI   |"));
    Serial.println(F("| LED will blink FAST (100ms).          |"));
    Serial.println(F("+---------------------------------------+"));
  } else {
    Serial.println();
    Serial.println(F("+---------------------------------------+"));
    Serial.println(F("| NRF24 NOT DETECTED — check wiring     |"));
    Serial.println(F("| LED will blink SLOW (1s).             |"));
    Serial.println(F("|                                       |"));
    Serial.println(F("| Common issues:                        |"));
    Serial.println(F("|  - VCC on 5V/VIN instead of 3.3V      |"));
    Serial.println(F("|  - MOSI/MISO swapped                  |"));
    Serial.println(F("|  - CE/CSN swapped                     |"));
    Serial.println(F("|  - Loose jumper (reseat all)          |"));
    Serial.println(F("|  - Missing decoupling cap on NRF24    |"));
    Serial.println(F("+---------------------------------------+"));
  }
}

void loop() {
  int onMs = wiringOk ? 100 : 1000;
  digitalWrite(LED_PIN, HIGH);
  delay(onMs);
  digitalWrite(LED_PIN, LOW);
  delay(onMs);
}
