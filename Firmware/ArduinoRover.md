# ESP32 + Arduino Mega rover experiment

Independent of the working micro:bit firmware. Existing iPhone app discovers
the Nordic UART service advertised as **ESP32 Rover**. Phone UI still uses the
micro:bit wording. No app changes required for the protocol.

Hardware: ESP32-D0WD-V3 on a 30-pin USB-C development board, Arduino Mega 2560,
HW-130 / L293D motor shield. Owner confirmed **left=M4, right=M1**.
Positive motor polarity still needs a wheels-lifted test. M2/M3 remain released.

## Current bench interlock

MegaRover has `DRIVE_ENABLED=false`: HELLO and PING work, ARM returns
`ERR:CONFIG`, and all four outputs stay at zero. This is deliberate until power
and serial wiring are checked. Do not enable automatically or run motor tests
without the owner. The original Mega flash and EEPROM are backed up locally,
outside the public repository. Original readable sketch was unavailable.

## Wiring (power off to connect)

Disconnect both old batteries and the HC-06. Use separate USB cables for the
two boards initially; do not join their VIN, 5V or 3V3 pins.

| ESP32 | Mega |
| --- | --- |
| GND | GND |
| TX2 / GPIO17 | RX1 / pin19 |
| RX2 / GPIO16 | TX1 / pin18 **through divider below** |

Mega TX1 pin18 → 1 kΩ resistor → junction → ESP32 RX2 GPIO16.
Junction → 2 kΩ resistor → common GND. This divides 5 V to approximately
3.33 V. Two 1 kΩ resistors in series can make the 2 kΩ leg. Never connect
Mega TX directly to ESP32 RX: ESP32 inputs are not 5 V tolerant.
Use known resistor values, not guessed colours from the old breadboard.
ESP32 TX goes directly to Mega RX. Both boards must be powered during use.

The shield's PWR jumper and 9.6 V pack routing still need inspection before
motor power is reintroduced. Do not feed the 9.6 V pack into ESP32 power pins.
Do not assume the yellow motors are rated for 9.6 V.

## Build

Arduino CLI, `arduino:avr@1.8.6`, `esp32:esp32@2.0.17`,
and `Adafruit Motor Shield library@1.0.1`.

```sh
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32@2.0.17 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli lib install 'Adafruit Motor Shield library@1.0.1'
arduino-cli compile --fqbn arduino:avr:mega Firmware/MegaRover --output-dir .build/MegaRover
arduino-cli compile --fqbn esp32:esp32:esp32 Firmware/ESP32Bridge --output-dir .build/ESP32Bridge
```

Discover serial ports before each upload. Upload separately to the matching
board only. Never use a full-chip erase as part of a normal upload.

## Behaviour and checks

- Mega implements the existing HELLO/ARM/D:left:right/STOP/PING protocol.
- Strict ±160 integer validation; boot, STOP, invalid command and watchdog
  expiry zero all outputs and disarm. Fresh drive required within 400 ms.
- Expired ARM cannot be revived by a late drive. PING does not renew it.
- USB on Mega is diagnostic output only, not a second drive-command source.
- ESP32 forwards replies from the actual Mega, never fabricates acknowledgements.
- UART baud=115200. Unwired Mega causes `ERR:MEGA_TIMEOUT` when connecting
  from the phone. This is expected until the three signal/ground connections exist.
- Bridge permits one outstanding command and times it out after 250 ms;
  timeout/overflow/malformed packets/disconnect request STOP. Mega's independent
  watchdog covers broken wires or a dead ESP32. BLE reconnection requires HELLO.
- BLE is not authenticated; Enable is a safety UI action, not access control.

Run `scripts/test.sh`. Native C++ tests exercise the actual Mega command gate,
including bench inhibition, malformed input, stale drive, timer rollover and stop.
Physical BLE→UART checks and wheels-lifted driving tests are separate requirements.

References: [Espressif BLE API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ble.html),
[Adafruit V1 motor shield](https://learn.adafruit.com/adafruit-motor-shield?view=all),
[Mega serial pins](https://store.arduino.cc/products/arduino-mega-2560-rev3).
