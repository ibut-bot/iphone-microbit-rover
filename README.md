# iPhone + micro:bit rover

A solder-free Bluetooth rover: a native SwiftUI joystick and hand-gesture app controls two motors on a Yahboom Super:bit board, through a micro:bit V2 running MakeCode firmware.

The front camera recognises hand gestures locally using Apple Vision, with an animated 3D guide available from the hand icon. No LiDAR, Apple Intelligence subscription, cloud processing or model download is required.

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

## Hand control

1. Put the phone upright on a stand with its **front camera facing you**; it does not need to ride on the rover.
2. Connect the micro:bit, select **Hand control**, and allow camera access.
3. Tap **Enable driving**, separate thumb and index finger, then pinch thumb and index finger together inside the joystick’s dashed centre circle for about 0.15 seconds to grab it. Only thumb and index landmarks are used. Your wrist and other fingers are ignored; steer with the midpoint between the two fingertips.
4. The translucent joystick turns green when grabbed, including while centred and stopped. Move the held pinch UP for forward, DOWN for reverse, LEFT/RIGHT to turn, or diagonally to combine movement and steering. Distance from centre sets power. Returning to the dashed centre zone stops movement.
5. Open the pinch to stop. Losing the hand, ambiguous/multiple hands or low-confidence landmarks also stops movement. Brief tracking loss stops immediately and requires returning to centre and a fresh pinch hold to resume; after loss longer than 0.6 seconds, show an open hand again.
6. Tap the **hand icon** at the top right for five animated 3D demonstrations, available even when disconnected. Opening the guide stops/disarms the rover; enable driving again after closing it.

Hand control opens an immersive camera screen. Connection, speed and wheel settings are hidden; tap **Exit** to return to them. Enable/STOP, the hand guide and recording remain available as small overlays. The rear-camera inset at bottom right shows the rover while the front camera tracks your fingers.

Hand mode supports forward, reverse and turns in place, and caps the speed setting at 35%. Its overlay and controller use the same displayed-image coordinates, radius and deadzone. Detection uses the full camera frame, then maps landmarks onto the preview; shorter stick travel keeps turns away from the edges. Index-finger scale is stabilized for up to 400 ms, but both fingertips must be detected live. Camera processing stays on the phone; nothing is uploaded. Frames are recorded locally only when you tap Record. Use good light, thumb/index tips and the index knuckle in view, and test first with wheels lifted. Landmark recognition and gesture thresholds still need physical testing across hands and lighting.

## Record both cameras

1. Connect the rover before entering Hand control. Aim the rear camera at the rover and the front camera at your hand.
2. Wait for both previews, then tap **Record**. The frame counter confirms video frames are being written; no screen-recording prompt is needed. Allow permission to add videos to Photos when saving. Microphone recording is off.
3. Recording starts with the rover disarmed; tap **Enable driving** when ready.
4. Tap **Stop recording** to finish. The app saves a single composited MP4 to **Photos**, including both cameras and joystick highlighting. Camera frames and joystick state are composited directly using AVAssetWriter; menus and buttons are not recorded.
5. A local copy is retained under **Files → On My iPhone → Microbit Link**. The **Recordings** list opens after saving and is available from the film-stack icon, including after relaunch. Use **Share / Save** or **Save to Photos** to recover/export a clip.

Exit, opening the guide, camera interruption or backgrounding stops recording and attempts to finalize/save. No microphone audio is captured. Wait for the save confirmation before force-quitting. Recording needs supported simultaneous front/rear cameras ; if the rear camera cannot start, hand control remains available but Record is disabled. Dual streams are configured at 15 fps with low-resolution supported formats to leave capacity for tracking.

## Stop behaviour and limitations

- Boot and connection set motor outputs to zero; ARM is required before movement.
- Release/gesture cancellation sends zero speed. STOP, either micro:bit button and disconnect disarm.
- The screen stays awake while the app is active. Leaving the app restores normal auto-lock and requests STOP; manually locking also requests STOP.
- The firmware disarms after more than 400 ms without a valid drive command, checked every 20 ms. Motors can coast after power removal.
- App sends at 10 Hz with one outstanding application acknowledgement, avoiding a backlog of movement packets. Missing replies for 350 ms cause a STOP attempt and disconnect.
- Firmware rejects malformed and out-of-range commands. Driver values are capped at ±160; the app slider permits 20–60% of the 255 scale.
- A separate 300 ms camera-frame timeout disables hand driving even if the Bluetooth command timer is still running. Mode changes and opening the guide/settings also stop and disarm.
- No encoders, obstacle avoidance, autonomous navigation or LiDAR integration yet.
- **Bluetooth currently uses No Pairing Required.** Nearby clients can connect; Enable is an interlock, not authentication. Resolve access control before broader use or distribution.
- Watchdogs are software controls, not a certified emergency stop. Test changes with wheels lifted.

## Code

| Path | Purpose |
|---|---|
| `App/MicrobitLink.swift` | SwiftUI app, BLE transport, joystick and wheel mixing |
| `App/HandCamera.swift` | Front-camera capture, mirrored preview and Vision landmarks |
| `App/HandControl.swift` | Testable gesture recognition interlock and steering |
| `App/RoverRecording.swift` | Immersive controls, rear-camera inset, direct camera-frame video composition, Photos/Files saving |
| `App/GestureGuide.swift` | Procedural articulated 3D hand demonstrations |
| `Firmware/main.ts` | MakeCode motor protocol, parsing and watchdog |
| `Firmware/pxt.json` | Firmware configuration and pinned Yahboom dependency |
| `Tests/` | Firmware, joystick mixing and gesture interlock checks |
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

Tests use stubbed hardware APIs, so they validate firmware logic, not electrical behaviour or radio latency. The mixing test extracts the implementation from the app source; gesture tests execute the actual camera-independent gate, including tracking loss, stale/out-of-order input, release, dwell and rearming. Simulator visual checks cover the guide and control layout; physical camera recognition is not simulated. Physical driving was reported working by the owner; detailed measurements of stopping distance, Bluetooth loss and loaded performance have not been made.

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

### Recording integration check (simulator)

Launch the simulator app with `--recording-smoke-test` to generate a three-second clip through the real compositor and AVAssetWriter, using clearly labelled synthetic front/rear images. Grant simulator Photos add access to test automatic export. The flag is compiled out on physical devices. `swift Tests/verify-video.swift /path/to/generated.mp4 /path/to/frame.png` checks duration, dimensions and decoding and extracts a frame for inspection. This does not validate physical camera performance.
