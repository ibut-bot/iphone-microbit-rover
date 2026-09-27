func command(_ text: String, _ direction: VoiceDirection, _ duration: Double) {
    guard let c = VoiceCommand.direct(text) else { fatalError("Did not parse: \(text)") }
    assert(c.direction == direction && c.duration == duration, text)
}
command("Rover, go forward!", .forward, 5)
command("Rover please move backwards", .reverse, 5)
command("Rover go left", .left, 1)
command("Rover, rotate right please", .right, 1)
command("Rover back up a little", .reverse, 1)
command("Rover turn left a little bit", .left, 0.5)
command("STOP", .stop, 0)
command("Rover forward stop", .stop, 0)
command("don't stop", .stop, 0) // Any stop word is deliberately conservative.
for invalid in ["go forward", "a rover go left", "rover", "rover don't go forward", "Rover don’t go left", "rover left and right", "rover forward then back", "rover left or forward", "rover go forward for 50 seconds", "rover turn left 90 degrees", "rover go forward until I say", "rover go fast forward", "rover not left", "rover go left if ready"] {
    assert(VoiceCommand.candidate(invalid) == nil, invalid)
    assert(VoiceCommand.direct(invalid) == nil, invalid)
}
assert(!VoiceCommand.containsStop("unstoppable"))
assert(VoiceCommand.direct("Rover could you move to the left please") == nil) // “to the” still uses optional intent parsing.
assert(VoiceCommand.candidate("Rover could you move to the left please")?.direction == .left)
var motion = VoiceMotionGate()
let forward = VoiceCommand(direction: .forward, small: false)
let left = VoiceCommand(direction: .left, small: false)
assert(!motion.start(forward, now: 1, enabled: false))
assert(motion.command == nil)
assert(motion.start(forward, now: 10, enabled: true))
assert(!motion.expire(now: 14.999))
assert(motion.expire(now: 15))
assert(motion.command == nil)
assert(!motion.expire(now: 16))
assert(motion.start(forward, now: 20, enabled: true))
assert(motion.start(left, now: 21, enabled: true))
assert(motion.deadline == 22 && motion.command == left)
assert(motion.expire(now: 25), "A delayed tick must stop, not extend movement")
assert(motion.start(forward, now: 30, enabled: true))
motion.cancel()
assert(motion.command == nil && !motion.expire(now: 31))
assert(!motion.start(forward, now: .nan, enabled: true))
assert(!motion.start(VoiceCommand(direction: .stop, small: false), now: 31, enabled: true))
assert(motion.start(forward, now: 40, enabled: true))
assert(motion.expire(now: .nan))
for direction in VoiceDirection.allCases where direction != .stop {
    let v = direction.vector
    let motors = RoverMix.motors(x: v.width, y: -v.height, limit: 0.25, swap: false, reverse1: false, reverse3: false)
    assert(abs(motors.0) <= 64 && abs(motors.1) <= 64)
    switch direction {
    case .forward: assert(motors.0 > 0 && motors.1 > 0)
    case .reverse: assert(motors.0 < 0 && motors.1 < 0)
    case .left: assert(motors.0 < 0 && motors.1 > 0)
    case .right: assert(motors.0 > 0 && motors.1 < 0)
    case .stop: break
    }
}
print("PASS: voice commands, wake prefix, negation/ambiguity rejection, stop precedence, motion deadlines, replacement/cancellation, low-speed direction mapping")

var cursor = VoiceTranscriptCursor()
typealias Segment = VoiceTranscriptCursor.Segment
let first = [Segment(text: "Rover", start: 0.1, duration: 0.4), Segment(text: "forward", start: 0.6, duration: 0.5)]
assert(cursor.pending(first) == "Rover forward")
cursor.consume(first)
assert(cursor.pending(first).isEmpty, "Repeated partial result must not repeat movement")
let second = first + [Segment(text: "Rover", start: 6.0, duration: 0.4), Segment(text: "left", start: 6.5, duration: 0.4)]
assert(cursor.pending(second) == "Rover left", "A second command must be accepted in the same recognition session")
cursor.consume(second)
let third = second + [Segment(text: "stop", start: 7.0, duration: 0.3)]
assert(VoiceCommand.containsStop(cursor.pending(third)))
cursor.consume(third)
assert(cursor.pending(third).isEmpty)
let fourth = third + [Segment(text: "Rover", start: 8.0, duration: 0.4), Segment(text: "right", start: 8.5, duration: 0.4)]
assert(VoiceCommand.direct(cursor.pending(fourth))?.direction == .right, "Stop in old transcript must not block next command")
assert(VoiceCommand.isIncomplete("Rover go"))
assert(!VoiceCommand.isIncomplete("Rover go left"))
var pending = PendingDriveInput()
pending.set(.init(width: 0, height: -1), voice: nil, now: 10)
assert(pending.take(now: 10.2) != nil)
assert(pending.take(now: 10.3) == nil)
pending.set(.init(width: -1, height: 0), voice: nil, now: 11)
assert(pending.take(now: 11.36) == nil, "Late ARM must not replay stale input")
pending.set(forward.direction.vector, voice: forward, now: 12)
pending.clear()
assert(pending.take(now: 12.1) == nil, "Release or STOP cancels ARM-pending motion")
pending.set(forward.direction.vector, voice: forward, now: 13)
assert(pending.take(now: 13.9)?.voice == forward)
print("PASS: consecutive speech, cumulative transcript deduplication, stop then new speech, incomplete wake phrase, fresh automatic-arm input and cancellation")

for direction in ["left", "right"] {
    for prefix in ["can you", "could you", "would you", "will you"] {
        command("Rover \(prefix) turn \(direction) a little", VoiceDirection(rawValue: direction)!, 0.5)
    }
}
for phrase in ["Rover can you not turn right a little", "Rover can you tell me about turning right", "Rover can you turn right and left", "Rover right can you", "can you turn right a little"] {
    assert(VoiceCommand.direct(phrase) == nil, phrase)
}
print("PASS: exact reported polite little-turn phrase and variants use direct parsing; negated/unrelated/compound phrases are rejected")
