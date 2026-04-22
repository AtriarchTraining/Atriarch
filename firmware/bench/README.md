# firmware/bench/

Throwaway-but-keep-handy diagnostic sketches. Not part of the drill system.
Use these when you suspect a hardware issue and want to test a single component
in isolation.

Per eng plan §1.13, this directory is also the future home of
`target_accel_test/` (currently untracked at repo root).

## What's here

### `esp32_blink/`
Minimum-viable ESP32 sanity test. Verifies:
- arduino-cli can compile for the ESP32 toolchain
- Flash + reset path works
- USB-C serial printing works at 115200 baud
- Onboard blue LED (GPIO 2) pulses 1 Hz

Flash with:
```
arduino-cli compile --fqbn esp32:esp32:esp32 firmware/bench/esp32_blink
arduino-cli upload  --fqbn esp32:esp32:esp32 --port /dev/cu.usbserial-X firmware/bench/esp32_blink
```

Used 2026-04-20 to verify the first HiLetgo ESP32 DevKit from the 3-pack
boots cleanly. MAC logged: `f4:2d:c9:6a:9b:08`.

### `nrf24_probe/`
Verifies an NRF24L01 module is wired correctly to an ESP32 per the Atriarch
transmitter pin map (VSPI: CE=22, CSN=21, SCK=18, MOSI=23, MISO=19). Signals
result via LED:
- FAST blink (100ms) = NRF24 responds over SPI (`radio.isChipConnected()==true`)
- SLOW blink (1s) = NRF24 not detected (check VCC=3V3, MOSI/MISO orientation,
  CE/CSN orientation, jumper seating, decoupling cap)

Flash with the same commands as above, swap `esp32_blink` for `nrf24_probe`.

Used 2026-04-20 as the Phase 2.5 wiring gate for the ESP32 transmitter port.
Result: FAST blink confirmed, advancing to Phase 3 firmware port.

## When to add to this directory

Any time you build a diagnostic sketch that's worth keeping around for the
next time someone asks "is this chip dead or is it my code?" — drop it here
with a short README update. Don't pollute `firmware/target/` or
`firmware/transmitter/` / `firmware/transmitter_esp32/` with test code.
