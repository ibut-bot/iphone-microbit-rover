#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node Tests/firmware.cjs
node Tests/led-firmware.cjs
mkdir -p .build/tests
c++ -std=c++11 -Wall -Wextra -Werror Tests/mega-protocol.cpp -o .build/tests/mega-protocol
.build/tests/mega-protocol
# Extract the actual implementation so the assertions cannot test a stale copy.
python3 - <<'PY'
from pathlib import Path
source = Path('App/MicrobitLink.swift').read_text()
start = source.index('enum RoverMix {')
end = source.index('struct ContentView: View {', start)
Path('.build/tests/mix-implementation.swift').write_text('import Foundation\n' + source[start:end])
Path('.build/tests/mix.swift').write_text('import Foundation\n' + source[start:end] + Path('Tests/mix-assertions.swift').read_text())
PY
swift .build/tests/mix.swift

cat .build/tests/mix-implementation.swift App/HandControl.swift Tests/hand-assertions.swift > .build/tests/hand.swift
swift .build/tests/hand.swift

cat .build/tests/mix-implementation.swift App/VoiceCommand.swift Tests/voice-assertions.swift > .build/tests/voice.swift
swift .build/tests/voice.swift

# Exercise the actual app state machine without creating a Bluetooth connection.
python3 - <<'PY'
from pathlib import Path
source = Path('App/MicrobitLink.swift').read_text()
source = source[source.index('struct NearbyBit:'):source.index('struct ContentView:')]
source = source.replace('private ', '')
source = source.replace('central = CBCentralManager(delegate: self, queue: .main)', '// No radio in tests.')
source = source.replace('guard ready, let peripheral, let writeCharacteristic else { return }', 'guard ready else { return }')
source = source.replace('peripheral.writeValue(Data((command + "\\n").utf8), for: writeCharacteristic, type: .withResponse)', 'testSent.append(command)')
source = source.replace('override init() {', 'var testSent: [String] = []\n    override init() {')
Path('.build/tests/link.swift').write_text('import SwiftUI\nimport CoreBluetooth\n' + Path('App/HandControl.swift').read_text() + Path('App/VoiceCommand.swift').read_text() + source + Path('Tests/link-assertions.swift').read_text())
PY
swift .build/tests/link.swift
