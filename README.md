# iPhone + micro:bit rover

A solder-free Bluetooth rover: a native SwiftUI joystick app controls two motors on a Yahboom Super:bit board, through a micro:bit V2 running MakeCode firmware.

The joystick supports differential steering, a speed limit, wheel reversal settings, release-to-stop, and an independent motor-command watchdog. An earlier LED/button Bluetooth proof of concept is included under `examples/led-poc`.

**Start a new development session with [HANDOVER.md](HANDOVER.md).**

## Hardware

- iPhone with Bluetooth; the current joystick does not require LiDAR. Tested on iPhone 17 Pro.
- Mac with Xcode for building and installing the app.
- micro:bit V2 plugged into a Yahboom Super:bit expansion board.
- Two Yahboom red DC motors: **M1 left, M3 right**, viewed from behind looking toward the micro:bit LED face.
- Board-compatible motor battery/power supply and chassis. USB power to the micro:bit alone may not power the motors.

No soldering, extra Bluetooth module, cloud service or internet connection is needed to drive. Firmware building uses Microsoft's cloud compiler.

## Install

### Firmware

Install Node.js/npm, then:

```sh
./scripts/build-firmware.sh
cp -X .build/microbit-rover.hex /Volumes/MICROBIT/microbit-rover.hex
```

The copy command is for macOS with the micro:bit attached by a data-capable USB cable. Flashing replaces its existing program. Wait for it to finish; check for `FAIL.TXT` on MICROBIT if flashing fails. The generated universal HEX supports micro:bit V2 and can be imported into MakeCode for editing.

### iPhone

1. Open `MicrobitLink.xcodeproj` in Xcode.
2. Select your Apple Account/Personal Team under Signing & Capabilities.
3. Replace `org.example.microbitlink` with your own unique bundle identifier.
4. Connect and unlock your iPhone; enable Developer Mode.
5. Select the phone as the run destination and Run.
6. Trust your development profile on the phone if prompted, and allow Bluetooth access.

No signing certificates, provisioning profiles or personal development-team ID are included. Free Personal Team provisioning normally needs renewal after seven days.

## Drive

1. Power the motor board. Lift the wheels for the first direction test.
2. Open **Microbit Link**, tap **Find micro:bit**, and select your board.
3. Wait for **Connected — tap Enable driving**. Default speed limit is 35%.
4. Tap **Enable driving**. Hold and move the joystick. Up is forward toward the LED face; sideways at centre turns in place.
5. Release to stop. Red **STOP** disables driving; tap Enable again to resume.

In **Wheel setup**, keep “M1 is the right wheel” off for the documented wiring. Reverse individual motors if forward input spins a wheel backward. Settings persist on the phone. Opening setup stops/disarms the rover.

## Stop behaviour and limitations

- Boot and connection set motor outputs to zero; ARM is required before movement.
- Release/gesture cancellation sends zero speed. STOP, either micro:bit button and disconnect disarm.
- Leaving the app or locking the phone requests STOP.
- The firmware disarms after more than 400 ms without a valid drive command, checked every 20 ms. Motors can coast after power removal.
- App sends at 10 Hz with one outstanding application acknowledgement, avoiding a backlog of movement packets. Missing replies for 350 ms cause a STOP attempt and disconnect.
- Firmware rejects malformed and out-of-range commands. Driver values are capped at ±160; the app slider permits 20–60% of the 255 scale.
- No encoders, obstacle avoidance, autonomous navigation, camera or LiDAR integration yet.
- **Bluetooth currently uses No Pairing Required.** Nearby clients can connect; Enable is an interlock, not authentication. Resolve access control before broader use or distribution.
- Watchdogs are software controls, not a certified emergency stop. Test changes with wheels lifted.

## Code

| Path | Purpose |
|---|---|
| `App/MicrobitLink.swift` | SwiftUI app, BLE transport, joystick and wheel mixing |
| `Firmware/main.ts` | MakeCode motor protocol, parsing and watchdog |
| `Firmware/pxt.json` | Firmware configuration and pinned Yahboom dependency |
| `Tests/` | Firmware handler and actual joystick mixing checks |
| `examples/led-poc/` | Original LED commands / button-return experiment |
| `scripts/` | Build and test entrypoints |

Yahboom SuperBitV2 is pinned to `2dc96afd11a4510601a9c4f55b94ae4b1a6ec229`. Build tooling uses pxt-microbit 9.1.1 and pxt 0.5.1. Transitive npm dependencies resolve on installation; this is not a fully reproducible offline toolchain.

## Validation

```sh
./scripts/test.sh
xcodebuild -project MicrobitLink.xcodeproj -scheme MicrobitLink \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Tests use stubbed hardware APIs, so they validate firmware logic, not electrical behaviour or radio latency. The mixing test extracts the implementation from the app source. Physical driving was reported working by the owner; detailed measurements of stopping distance, Bluetooth loss and loaded performance have not been made.

## UART protocol

Service UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`. Short ASCII messages terminated by LF. Characteristics are discovered by write/indicate properties. Incoming fragmented replies are buffered.

| Command | Reply | Effect |
|---|---|---|
| `HELLO` | `ROVER:1` | Identify firmware and disarm |
| `ARM` | `OK:ARM` | Enable with initial zero output |
| `D:m1:m3` | `OK:D` | Signed motor outputs; refresh watchdog |
| `STOP` | `OK:STOP` | Stop and disarm |
| `PING` | `PONG` | Connectivity check |

Physical buttons send `SAFE:BUTTON`; watchdog sends `SAFE:TIMEOUT`. Invalid commands send `ERR:…` and disarm. All current messages fit within 20 bytes including newline.

## Dependencies and reuse

This repository references MakeCode and Yahboom open-source packages; their licences remain with their respective authors. Generated binaries and downloaded dependencies are not committed. No additional licence is granted for the original code in this repository yet; choose one before distributing it as an open-source kit or product. Public visibility alone is not an open-source licence.
