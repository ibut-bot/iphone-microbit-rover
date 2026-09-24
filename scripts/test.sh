#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node Tests/firmware.cjs
node Tests/led-firmware.cjs
mkdir -p .build/tests
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
