# micro:bit rover firmware

Download `microbit-rover.hex` and copy it to the MICROBIT drive. This replaces the
existing program. Use a micro:bit V2, Yahboom Super:bit board and M1-left/M3-right
DC motors. Keep motor power off while flashing. No Arduino/ESP32 hardware is needed.

This is the existing build used by the working micro:bit rover. The saved build
inputs match `Firmware/main.ts` and `Firmware/pxt.json` byte for byte. Intel HEX
record lengths and checksums were revalidated before publication.

SHA-256: `3ae207ed5ecbf5ddf053f765b6b05ae2694b0d3e9a535007c90f1856d4856b86`

To rebuild from source with Node.js/npm and internet:

```sh
bash scripts/build-firmware.sh
```

The app handles ARM automatically for fresh input. The firmware still requires ARM,
disarms on STOP/buttons/disconnect, and retains its 400 ms watchdog.
