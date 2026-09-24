var gate = HandDriveGate()
var time = 10.0
func sample(_ ratio: Double, x: Double = 0.5, fingers: Bool = true, age: Double = 0, enabled: Bool = true) -> HandDecision {
    time += 0.1
    return gate.evaluate(HandSample(palmX: x, pinchRatio: ratio, otherFingersExtended: fingers, capturedAt: time - age), now: time, enabled: enabled)
}
func drive() {
    assert(!sample(0.8).moving)
    assert(!sample(0.1).moving)
    assert(!sample(0.1).moving)
    assert(!sample(0.1).moving)
    assert(sample(0.1).moving)
}
assert(!sample(0.1).moving, "Must open before first pinch")
drive()
assert(sample(0.35).moving, "Hysteresis holds a recognized pinch")
assert(sample(0.1, x: 0).steering < 0)
assert(sample(0.1, x: 1).steering > 0)
assert(sample(0.1, x: 0.55).steering == 0)
assert(!sample(0.5).moving, "Release must stop immediately")
assert(!sample(0.1).moving, "A new pinch needs a fresh dwell")
assert(!gate.evaluate(nil, now: time, enabled: true).moving)
assert(!sample(0.1).moving, "Tracking loss requires opening again")
drive()
assert(!sample(0.1, age: 0.31).moving, "Stale inference must stop")
assert(!sample(0.1).moving)
drive()
assert(!sample(0.1, fingers: false).moving, "A fist must stop")
assert(!sample(0.1).moving)
drive()
assert(!sample(0.1, enabled: false).moving)
assert(!sample(0.1).moving, "Rearming requires open hand")
drive()
time += 1
assert(!sample(0.1).moving, "Frame gap invalidates held pinch")
drive()
assert(!sample(0.1, age: 0.15).moving, "Out-of-order frame stops movement")
for invalid in [Double.nan, Double.infinity, -Double.infinity] {
    assert(!sample(invalid).moving)
    assert(!sample(0.1, x: invalid).moving)
}
assert(!sample(0.1, age: -1).moving, "Future frame rejected")
gate.reset()
assert(!sample(0.1).moving)
print("Hand gesture tests passed: opening, dwell, steering, release, loss, freshness, ambiguity and rearming")
