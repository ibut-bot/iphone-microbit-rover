import Foundation

/// Coordinates refer to the same upright, mirrored image shown in the preview.
struct HandSample {
    let pinchX: Double
    let pinchRatio: Double // Tip distance divided by estimated index-finger length.
    let capturedAt: TimeInterval
}

struct HandDecision {
    var steering = 0.0
    var forward = 0.0
    var message: String
    var moving: Bool { forward > 0 }
}

struct HandDriveGate {
    static let maxFrameAge: TimeInterval = 0.30
    static let leftBoundary = 0.40
    static let rightBoundary = 0.60
    private var sawOpenHand = false
    private var pinchStarted: TimeInterval?
    private var pinching = false
    private var lastSampleAt: TimeInterval?
    private var direction = 0

    mutating func reset() {
        sawOpenHand = false; pinchStarted = nil; pinching = false
        lastSampleAt = nil; direction = 0
    }
    mutating func evaluate(_ sample: HandSample?, now: TimeInterval, enabled: Bool) -> HandDecision {
        guard enabled else {
            reset()
            return HandDecision(message: "Enable driving · separate thumb and index")
        }
        guard let sample else {
            // Stop immediately, but don't require another open-hand ritual for one dropped frame.
            // Reacquisition still needs a new pinch dwell; a sustained loss fully resets the gate.
            pinching = false; pinchStarted = nil; direction = 0
            if let last = lastSampleAt, now - last > 0.6 { reset() }
            return HandDecision(message: "Hand not clear — stopped")
        }
        guard sample.pinchX.isFinite, sample.pinchRatio.isFinite,
              sample.pinchX >= 0, sample.pinchX <= 1, sample.pinchRatio >= 0,
              now >= sample.capturedAt, now - sample.capturedAt <= Self.maxFrameAge else {
            reset()
            return HandDecision(message: "Tracking delayed — stopped")
        }
        if let last = lastSampleAt {
            if sample.capturedAt <= last || sample.capturedAt - last > 0.6 { reset() }
            else if sample.capturedAt - last > Self.maxFrameAge { pinching = false; pinchStarted = nil; direction = 0 }
        }
        lastSampleAt = sample.capturedAt
        if sample.pinchRatio >= 0.85 {
            sawOpenHand = true; pinchStarted = nil; pinching = false; direction = 0
            return HandDecision(message: "Ready · pinch to drive")
        }
        guard sawOpenHand else { return HandDecision(message: "Open thumb and index finger first") }
        if sample.pinchRatio <= 0.42 {
            if pinchStarted == nil { pinchStarted = sample.capturedAt }
            if sample.capturedAt - (pinchStarted ?? sample.capturedAt) >= 0.15 { pinching = true }
        } else if sample.pinchRatio > 0.70 {
            pinching = false; pinchStarted = nil; direction = 0
            return HandDecision(message: "Pinch released — stopped")
        } else if !pinching { pinchStarted = nil }
        guard pinching else { return HandDecision(message: "Hold pinch briefly…") }

        // Broad zones with hysteresis: small landmark jitter cannot flip a turn on/off.
        if sample.pinchX < Self.leftBoundary { direction = -1 }
        else if sample.pinchX > Self.rightBoundary { direction = 1 }
        else if direction == -1 && sample.pinchX >= 0.46 { direction = 0 }
        else if direction == 1 && sample.pinchX <= 0.54 { direction = 0 }
        if direction == 0 { return HandDecision(forward: 0.85, message: "FORWARD · open pinch to stop") }
        // Equal forward/turn values stop the inside wheel, instead of relying on tiny
        // PWM differences that small geared motors may not reproduce under load.
        return HandDecision(steering: Double(direction) * 0.45, forward: 0.45,
                            message: direction < 0 ? "LEFT · open pinch to stop" : "RIGHT · open pinch to stop")
    }
}
