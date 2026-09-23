#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo_dir="$PWD"
mkdir -p .build-tools/node_modules .build-tools/firmware .build
if [ ! -f .build-tools/package.json ]; then
  printf '%s\n' '{"private":true,"dependencies":{"pxt":"0.5.1","pxt-microbit":"9.1.1"}}' > .build-tools/package.json
fi
npm install --prefix .build-tools
printf '%s\n' '{"targetdir":"pxt-microbit"}' > .build-tools/node_modules/pxtcli.json
cp Firmware/main.ts Firmware/pxt.json .build-tools/firmware/
cd .build-tools/firmware
../node_modules/.bin/pxt install
../node_modules/.bin/pxt build --cloud
cp built/binary.hex "$repo_dir/.build/microbit-rover.hex"
printf 'Built %s\n' "$repo_dir/.build/microbit-rover.hex"
