// ESP32 sanity check — Atriarch Gate 1 #10.5 Phase 1
// Blinks the onboard LED (GPIO 2) and prints heartbeat over USB serial.
// If you see the blue LED pulsing + serial output, the toolchain and
// USB-C flashing path are fully alive.

const int LED_PIN = 2;  // onboard blue LED on most ESP32-WROOM-32 DevKits

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println();
  Serial.println("=== ESP32 Blink Test — Atriarch ===");
  Serial.print("MAC: ");
  uint64_t mac = ESP.getEfuseMac();
  Serial.printf("%04X%08X\n", (uint16_t)(mac >> 32), (uint32_t)mac);
  Serial.print("Chip model: ");
  Serial.println(ESP.getChipModel());
  Serial.print("CPU MHz: ");
  Serial.println(ESP.getCpuFreqMHz());
  Serial.print("Free heap: ");
  Serial.println(ESP.getFreeHeap());
  pinMode(LED_PIN, OUTPUT);
  Serial.println("Starting blink loop...");
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  Serial.println("LED on");
  delay(500);
  digitalWrite(LED_PIN, LOW);
  Serial.println("LED off");
  delay(500);
}
