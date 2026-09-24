var gate = HandDriveGate()
var time = 10.0
func sample(_ ratio: Double, x: Double = 0.5, age: Double = 0, enabled: Bool = true) -> HandDecision {
    time += 0.1
    return gate.evaluate(HandSample(palmX: x, pinchRatio: ratio, capturedAt: time - age), now: time, enabled: enabled)
}
func drive() {
    assert(!sample(1.1).moving)
    assert(!sample(0.2).moving)
    assert(!sample(0.2).moving)
    assert(sample(0.2).moving)
}
assert(!sample(0.2).moving)
drive()
assert(sample(0.6).moving, "Held pinch tolerates jitter")
let left = sample(0.2, x: 0.35)
assert(left.steering < 0 && left.forward == -left.steering)
assert(sample(0.2, x: 0.42).steering < 0, "Left zone hysteresis")
assert(sample(0.2, x: 0.47).steering == 0)
let right = sample(0.2, x: 0.65)
assert(right.steering > 0 && right.forward == right.steering)
assert(sample(0.2, x: 0.58).steering > 0, "Right zone hysteresis")
assert(sample(0.2, x: 0.53).steering == 0)
assert(!sample(0.75).moving, "Release stops immediately")
assert(!sample(0.2).moving, "Fresh pinch needs dwell")
drive()
assert(!gate.evaluate(nil, now: time, enabled: true).moving, "Dropped frame stops immediately")
assert(!sample(0.2).moving)
assert(!sample(0.2).moving)
assert(sample(0.2).moving, "Brief dropout can recover after fresh dwell")
assert(!gate.evaluate(nil, now: time + 0.7, enabled: true).moving)
time += 0.7
assert(!sample(0.2).moving, "Sustained loss requires open hand again")
drive()
assert(!sample(0.2, age: 0.31).moving)
assert(!sample(0.2).moving)
drive()
assert(!sample(0.2, enabled: false).moving)
assert(!sample(0.2).moving)
drive()
time += 1
assert(!sample(0.2).moving)
drive()
assert(!sample(0.2, age: 0.15).moving)
for invalid in [Double.nan, Double.infinity, -Double.infinity] {
    assert(!sample(invalid).moving)
    assert(!sample(0.2, x: invalid).moving)
}
assert(!sample(0.2, age: -1).moving)
// Run gate decisions through the actual wheel mixer: wiring is M1 left / M3 right.
let lm = RoverMix.motors(x: left.steering, y: left.forward, limit: 0.35, swap: false, reverse1: false, reverse3: false)
let rm = RoverMix.motors(x: right.steering, y: right.forward, limit: 0.35, swap: false, reverse1: false, reverse3: false)
assert(lm.0 == 0 && lm.1 > 60, "Left must power right wheel and stop left")
assert(rm.1 == 0 && rm.0 == lm.1, "Right must be the symmetric wheel command")
print("PASS: hand zones, hysteresis, symmetric motor turns, pinch tolerance, immediate loss/release stop, recovery dwell, stale frames and rearming")
