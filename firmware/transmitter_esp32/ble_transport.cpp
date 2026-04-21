// firmware/transmitter_esp32/ble_transport.cpp
//
// NimBLE-Arduino 2.5.x peripheral wrapper. See ble_transport.h for the
// threading model and design notes.

#include "ble_transport.h"
#include "config.h"

#include <NimBLEDevice.h>
#include <NimBLEServer.h>
#include <NimBLEService.h>
#include <NimBLECharacteristic.h>
#include <NimBLEAdvertising.h>

#include <stdarg.h>
#include <string.h>

// Single instance; declared extern in the header so the sketch can call it
// directly. Constructed with zero state; begin() fills it in.
BleTransport ble;

// FreeRTOS spinlock guarding the inbound ring buffer. portMUX is the
// idiomatic short-critical-section primitive on ESP32 dual-core (it disables
// interrupts on the current core and spins for the other core's cache line).
// We only hold it for a handful of byte copies / index updates — never across
// logging, heap alloc, or NimBLE calls.
static portMUX_TYPE s_rxMux = portMUX_INITIALIZER_UNLOCKED;

// ----- Callback plumbing -----------------------------------------------------

// Inbound: app writes to our characteristic.
class RxCallbacks : public NimBLECharacteristicCallbacks {
public:
  // NimBLE-Arduino 2.x onWrite signature takes (char*, ConnInfo&). We ignore
  // the ConnInfo for now — the app opens one connection at a time.
  void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& /*connInfo*/) override {
    const NimBLEAttValue& v = pCharacteristic->getValue();
    const uint8_t* data = v.data();
    size_t len = v.size();
    if (len > 0 && data != nullptr) {
      ble.pushRx(data, len);
    }
  }
};

// Connection state tracking + re-advertise on disconnect.
class ServerCallbacks : public NimBLEServerCallbacks {
public:
  void onConnect(NimBLEServer* /*pServer*/, NimBLEConnInfo& /*connInfo*/) override {
    ble.setConnected(true);
    Serial.println("[BLE] central connected");
  }
  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& /*connInfo*/, int reason) override {
    ble.setConnected(false);
    Serial.printf("[BLE] central disconnected (reason=%d), restarting advertising\n", reason);
    // NimBLE 2.x: re-start advertising so the app can reconnect.
    NimBLEDevice::getAdvertising()->start();
  }
};

static RxCallbacks     s_rxCb;
static ServerCallbacks s_serverCb;

// ----- BleTransport ---------------------------------------------------------

BleTransport::BleTransport()
    : rxBuf_(nullptr),
      rxCap_(0),
      rxHead_(0),
      rxTail_(0),
      rxCount_(0),
      server_(nullptr),
      characteristic_(nullptr),
      connected_(false) {}

void BleTransport::begin() {
  // Allocate the ring buffer once. (Heap-alloc rather than static array so
  // BLE_RX_BUF_SIZE is the single source of truth in config.h.)
  rxCap_ = BLE_RX_BUF_SIZE;
  rxBuf_ = (uint8_t*)malloc(rxCap_);
  // If malloc fails the device is unrecoverable; crash loudly rather than
  // corrupting memory by writing to nullptr later.
  if (rxBuf_ == nullptr) {
    Serial.println("[BLE] FATAL: rxBuf malloc failed");
    while (true) { delay(1000); }
  }

  NimBLEDevice::init(BLE_DEVICE_NAME);
  // Reasonable TX power default; HM-10 was ~+0 dBm. Leave NimBLE default
  // (+3 dBm on WROOM-32) so range is at least as good as the Nano rig.
  // TODO(port): if RF interferes with NRF24 at very short range, drop to
  // ESP_PWR_LVL_N3 via NimBLEDevice::setPower().

  server_ = NimBLEDevice::createServer();
  server_->setCallbacks(&s_serverCb);

  NimBLEService* service = server_->createService(BLE_SERVICE_UUID);

  characteristic_ = service->createCharacteristic(
      BLE_CHAR_UUID,
      NIMBLE_PROPERTY::READ
    | NIMBLE_PROPERTY::WRITE
    | NIMBLE_PROPERTY::WRITE_NR
    | NIMBLE_PROPERTY::NOTIFY
  );
  characteristic_->setCallbacks(&s_rxCb);

  service->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(BLE_SERVICE_UUID);
  adv->setName(BLE_DEVICE_NAME);
  // NimBLE 2.x default advertising interval (~100 ms) is fine.
  adv->start();

  Serial.print("[BLE] advertising as ");
  Serial.println(BLE_DEVICE_NAME);
}

// ----- Inbound ring buffer --------------------------------------------------

bool BleTransport::available() const {
  // Atomic read of a size_t is safe on 32-bit ESP32 for the quick-check path.
  // Worst case we see a slightly stale count; read() will recheck under lock.
  return rxCount_ > 0;
}

int BleTransport::read() {
  int result = -1;
  portENTER_CRITICAL(&s_rxMux);
  if (rxCount_ > 0) {
    result = rxBuf_[rxTail_];
    rxTail_ = (rxTail_ + 1) % rxCap_;
    rxCount_--;
  }
  portEXIT_CRITICAL(&s_rxMux);
  return result;
}

void BleTransport::pushRx(const uint8_t* buf, size_t len) {
  if (buf == nullptr || len == 0 || rxBuf_ == nullptr) return;
  portENTER_CRITICAL(&s_rxMux);
  for (size_t i = 0; i < len; i++) {
    if (rxCount_ >= rxCap_) {
      // Buffer full — drop the byte. This should never happen in practice
      // (longest command ~200 bytes, buffer is 512), but if it does, we'd
      // rather drop than clobber. Record nothing here; we're inside the
      // critical section and logging would be unsafe.
      break;
    }
    rxBuf_[rxHead_] = buf[i];
    rxHead_ = (rxHead_ + 1) % rxCap_;
    rxCount_++;
  }
  portEXIT_CRITICAL(&s_rxMux);
}

// ----- Outbound notifications -----------------------------------------------

void BleTransport::write(const uint8_t* buf, size_t len) {
  if (characteristic_ == nullptr || buf == nullptr || len == 0) return;
  if (!connected_) {
    // No central connected — nothing to notify. Don't buffer; the app
    // re-requests SNAP/ on reconnect anyway.
    return;
  }
  // setValue + notify. Chunk at 20 bytes to stay under the default MTU of 23
  // (3 bytes ATT overhead). NimBLE negotiates higher MTUs when the central
  // requests it, but our Flutter app already chunks writes to 20 and the
  // protocol is slash-delimited so splitting is safe mid-stream.
  const size_t CHUNK = 20;
  size_t off = 0;
  while (off < len) {
    size_t n = (len - off > CHUNK) ? CHUNK : (len - off);
    characteristic_->setValue(buf + off, n);
    characteristic_->notify();
    off += n;
  }
}

void BleTransport::print(const char* s) {
  if (s == nullptr) return;
  write(reinterpret_cast<const uint8_t*>(s), strlen(s));
}

void BleTransport::println(const char* s) {
  print(s);
  // Send the '\n' as a separate byte to preserve the same wire format the
  // Nano produced. Low-volume path; avoiding a strcat + heap alloc.
  const uint8_t nl = '\n';
  write(&nl, 1);
}

int BleTransport::printf(const char* fmt, ...) {
  char buf[128];
  va_list args;
  va_start(args, fmt);
  int n = vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  if (n > 0) {
    size_t emit = (n < (int)sizeof(buf)) ? (size_t)n : sizeof(buf) - 1;
    write(reinterpret_cast<const uint8_t*>(buf), emit);
  }
  return n;
}

bool BleTransport::isConnected() const {
  return connected_;
}

void BleTransport::setConnected(bool c) {
  connected_ = c;
}
