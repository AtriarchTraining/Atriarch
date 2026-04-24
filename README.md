# Atriarch

Wireless reactive target training system for shooting, reaction, law enforcement, and competition-style drills.

## Architecture

- **Flutter App** (iOS/Android) — drill configuration, timer, post-drill results
- **Transmitter** (ATmega328P + HM-10 BLE + NRF24L01) — drill orchestration
- **Targets** (Arduino Nano + NRF24L01 + WS2812 + vibration sensor) — up to 30 units

See `docs/superpowers/specs/` for the full system design spec.

## Development

```bash
flutter pub get
flutter run
```

Firmware is in `firmware/target/` and `firmware/transmitter/`. Open in Arduino IDE.
