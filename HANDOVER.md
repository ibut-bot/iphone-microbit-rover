# Handover for a fresh experiment session

## Paste into the new context

> Continue development of https://github.com/ibut-bot/iphone-microbit-rover. Read HANDOVER.md and README.md first. This is a iPhone Bluetooth joystick and camera gesture app controlling a micro:bit V2 on a Yahboom Super:bit board. M1 is left and M3 is right. Preserve the existing driving mode and motor watchdog while we develop the next experiment. Inspect the checkout and attached devices; do not drive motors automatically. Ask me which experiment to start.

## Confirmed working baseline

- SwiftUI/Core Bluetooth app named **Microbit Link**, screen title **Microbit Rover**, on iPhone 17 Pro.
- micro:bit V2, Yahboom Building:bit Super Kit / Super:bit expansion board, two red DC drive motors on **M1 left / M3 right**.
- Motors are at the rear, away from the micro:bit LED face. Looking forward toward that face, M1 is left.
- The grey kit unit is a positional servo and is not currently used.
- Runtime is wireless BLE; USB is only for programming/power. Use the expansion board's intended motor supply.
- Owner confirmed the original Bluetooth POC and subsequent joystick rover both work as expected. No formal payload/latency/stopping-distance measurements were made.

## Development setup and installation

Originally built with Xcode 26.5, iOS SDK 26.5, physical iPhone on iOS 26.6. Developer Mode and local Personal Team signing were configured. App and firmware were installed; owner handled keychain and phone developer-trust prompts.

The public Xcode project omits the signing team and uses **org.example.microbitlink**. Choose a unique bundle ID and the owner's team locally. The previously installed app used a different ID: inspect the old local project/device if updating it, rather than guessing. A changed ID installs a separate app and resets wheel preferences.

The previous operational project remains in the original session's outputs/MicrobitLink directory. This public repo was copied from it to keep that working setup intact. Use this repo as the source of truth for new experiments. Do not run old scratch project-generation scripts over the current Xcode project.

Generated HEX files are not committed; build with scripts/build-firmware.sh. The original LED-only App and firmware source are under examples/led-poc, outside the rover Xcode target. Build that firmware separately using its pxt.json/main.ts if needed.

## Architecture / protocol

App/MicrobitLink.swift currently contains:

- **BluetoothLink**: BLE scan/connection, UART service discovery, HELLO compatibility handshake, acknowledgement handling, 10 Hz command timer, logs.
- **RoverMix**: deadzone, forward/turn differential mixing, wheel swap/reversal, speed limits.
- **ContentView**: spring-centred joystick, hand-mode selection, connection controls, enable/stop, speed and wheel settings.

App/HandCamera.swift captures mirrored portrait front-camera frames and extracts Apple Vision hand landmarks at up to 15 Hz. App/HandControl.swift owns a pure, testable gesture gate: open hand after enable/loss, thumb/index pinch held 250 ms to move, lateral palm position to steer, immediate zero on release/invalid hand. Hand mode is forward-only, capped at 35% power. BluetoothLink independently disarms if camera callbacks stall for 300 ms. App/GestureGuide.swift renders procedural SceneKit 3D animations for forward/left/right/stop. The toolbar hand icon always opens it, stops the rover and pauses the camera. Closing it requires rearming. Camera frames are processed locally without recording or upload.

Firmware/main.ts uses Yahboom SuperBitV2 MotorRun for M1/M3, a strict integer parser and watchdog. The extension is pinned in pxt.json. Do not replace motor direction handling without checking the vendor driver.

UART service UUID: **6E400001-B5A3-F393-E0A9-E50E24DCCA9E**. ASCII newline-delimited messages; directions are discovered by characteristic properties rather than ambiguous TX/RX names. Full protocol is in README.

Preserve these behaviours:

- Boot/connection starts with zero outputs; ARM required for motion.
- Firmware rejects malformed or out-of-range ±160 motor commands and disarms.
- HELLO, STOP, disconnect and either micro:bit button stop/disarm.
- Fresh D:m1:m3 required within 400 ms; watchdog checks every 20 ms and disarms on expiry.
- App has one outstanding application acknowledgement, not an accumulating drive queue.
- App reply timeout is 350 ms: attempt STOP and disconnect; firmware watchdog is fallback.
- Joystick release/cancellation sends zero. STOP disables driving until re-enabled.
- Switching apps/locking requests STOP. Motors can coast after power is removed.
- Speed defaults to 35%, adjustable 20–60%. Wheel settings persist in phone preferences.
- Firmware uses **No Pairing Required**. Nearby clients can connect; Enable is not authentication.

## Validation workflow

1. Run scripts/test.sh (Node, Swift, Python 3). Firmware hardware APIs are stubbed; joystick tests extract the actual RoverMix code.
2. Run README's unsigned Xcode build, then build firmware.
3. Discover attached devices with `xcrun devicectl list devices`; do not reuse old device IDs blindly.
4. Select local Personal Team for signed build. Never commit certificates, keys, provisioning profiles or Xcode user state.
5. Install with Xcode/devicectl. Ask the owner to unlock the phone or handle local password/trust prompts when needed.
6. Flash only the intended attached micro:bit. macOS `cp -X` avoids extended-attribute failures on DAPLink. Check FAIL.TXT afterwards.
7. First motor test with wheels lifted and owner in control: forward/reverse, steering, release, STOP, physical buttons and signal loss.

## Known limitations

- Tests do not exercise actual BLE timing, UIKit/SwiftUI interruptions, physical torque, stopping distance or radio loss.
- No encoders, acceleration ramp, autonomous navigation, LiDAR or obstacle detection implemented. Camera hand control is implemented; recognition quality, mirrored steering and physical stop latency still need owner testing.
- Simulator UI was checked for iPhone 17 Pro; simulator Bluetooth is unavailable as expected.
- Personal Team install needs periodic renewal; no App Store/TestFlight distribution.
- Toolchain is pinned at top level, but transitive dependencies are not fully locked/offline.
- Public code currently has no licence grant; choose one deliberately before open-source distribution or reuse.
- This hobby prototype has not undergone product compliance assessment.

## Current experiment and future ideas

Hand control and its animated 3D guide were added on 2026-09-24, with signed device and simulator builds and passing firmware/mixing/gesture tests. Firmware is unchanged; do not reflash for this update. The update was installed successfully on the attached iPhone; automatic launch was blocked because the phone was locked. The owner must open Microbit Link, select Hand control and allow Camera. The owner has not yet confirmed hand-controlled physical driving.

Other ideas: tilt-to-drive; camera/LiDAR obstacle-aware driving with phone mounted; coloured-ball following; overhead marker/ball tracking. Preserve manual override and stop on invalid depth, lost target or lost pose tracking in any autonomous mode.

A printed phone cradle is a possibility, not yet built. Capacity is unverified. Suggested low, central landscape mount with rear cameras facing forward and a secured dummy-load test first. Do not assume motor torque or battery capacity from appearance.

Owner has access to a Bambu H2D multi-material printer and also Arduino/ESP32 boards, yellow motors and NiMH batteries. Prefers solder-free, plug-in builds after previous power-wiring failures damaged Arduino boards. Maintain the integrated motor/power board approach unless a verified alternative is selected.

Student kit sales were discussed separately as a possible future business, not part of the implemented software.
