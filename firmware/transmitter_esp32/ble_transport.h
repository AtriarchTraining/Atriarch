// firmware/transmitter_esp32/ble_transport.h
//
// Thin wrapper around NimBLE-Arduino (2.5.x) that exposes a Serial-like
// byte pipe: read() / available() for inbound bytes written by the central
// (the Flutter app), and write/print/printf for outbound notifications.
//
// Threading model:
//   - NimBLE runs its GATT server on a FreeRTOS task ("nimble_host" / "btc").
//     onWrite() callbacks fire from that task.
//   - The main Arduino loop() runs in app_main's task.
// The inbound ring buffer is shared between these two tasks. We guard it
// with a FreeRTOS portMUX spinlock (portENTER_CRITICAL / portEXIT_CRITICAL)
// which is the ESP-IDF idiom for short critical sections on dual-core ESP32.
// All shared state (head/tail/count) is touched only inside the critical
// section; the byte array itself is accessed only under the lock.

#ifndef BLE_TRANSPORT_H
#define BLE_TRANSPORT_H

#include <Arduino.h>
#include <stddef.h>
#include <stdint.h>

// Forward-declare NimBLE types so consumers don't drag the whole header in.
class NimBLEServer;
class NimBLECharacteristic;

class BleTransport {
public:
  BleTransport();

  // Initialize NimBLE, create service + characteristic, start advertising.
  // Safe to call once from setup() after Serial.begin().
  void begin();

  // Inbound (central -> peripheral, i.e. app -> transmitter).
  // Reads bytes that arrived via the characteristic's onWrite callback.
  bool available() const;
  int  read();                     // -1 if empty

  // Outbound (peripheral -> central, i.e. transmitter -> app).
  // Sends via characteristic notify. No-ops if no central is connected.
  void write(const uint8_t* buf, size_t len);
  void print(const char* s);
  void println(const char* s);     // appends '\n'
  int  printf(const char* fmt, ...) __attribute__((format(printf, 2, 3)));

  // True while a central is connected (GATT session active).
  bool isConnected() const;

  // Internal: called from NimBLE callback task to push inbound bytes.
  // Public so the callback class can invoke it without friend acrobatics.
  void pushRx(const uint8_t* buf, size_t len);

  // Internal: called from NimBLE callbacks to update connection state.
  void setConnected(bool c);

private:
  // Ring buffer for inbound bytes. Sized from config.h (BLE_RX_BUF_SIZE).
  uint8_t* rxBuf_;
  size_t   rxCap_;
  volatile size_t rxHead_;   // write index (pushed by BT task)
  volatile size_t rxTail_;   // read index  (pulled by main loop)
  volatile size_t rxCount_;  // number of bytes currently buffered

  NimBLEServer*         server_;
  NimBLECharacteristic* characteristic_;
  volatile bool         connected_;
};

extern BleTransport ble;

#endif
