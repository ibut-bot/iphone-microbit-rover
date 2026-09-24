import Foundation

/// Camera-independent input, making the gesture interlock testable without Vision or hardware.
struct HandSample {
    let palmX: Double             // Mirrored preview coordinates: 0 left, 1 right.
    let pinchRatio: Double        // Thumb/index tip distance divided by palm width.
    let otherFingersExtended: Bool
    let capturedAt: TimeInterval  // Monotonic time before inference starts.
}

struct HandDecision {
    var steering = 0.0
    var forward = 0.0
    var message: String
    var moving: Bool { forward > 0 }
}

struct HandDriveGate {
    static let maxFrameAge: TimeInterval = 0.30
    private var sawOpenHand = false
    private var pinchStarted: TimeInterval?
    private var pinching = false
    private var lastSampleAt: TimeInterval?

    mutating func reset() {
        sawOpenHand = false; pinchStarted = nil; pinching = false; lastSampleAt = nil
    }
    mutating func evaluate(_ sample: HandSample?, now: TimeInterval, enabled: Bool) -> HandDecision {
        guard let sample, sample.palmX.isFinite, sample.pinchRatio.isFinite,
              sample.palmX >= 0, sample.palmX <= 1, sample.pinchRatio >= 0,
              now >= sample.capturedAt, now - sample.capturedAt <= Self.maxFrameAge else {
            reset()
            return HandDecision(message: "No clear hand — stopped")
        }
        guard enabled else {
            reset()
            return HandDecision(message: "Hand visible · enable driving to begin")
        }
        // A gap or out-of-order frame cannot continue an earlier held gesture.
        if let last = lastSampleAt, sample.capturedAt <= last || sample.capturedAt - last > Self.maxFrameAge {
            reset()
        }
        lastSampleAt = sample.capturedAt
        guard sample.otherFingersExtended else {
            sawOpenHand = false; pinchStarted = nil; pinching = false
            return HandDecision(message: "Keep your other fingers open — stopped")
        }
        if sample.pinchRatio >= 0.55 {
            sawOpenHand = true; pinchStarted = nil; pinching = false
            return HandDecision(message: "Ready · pinch thumb and index to drive")
        }
        guard sawOpenHand else { return HandDecision(message: "Open your hand first") }
        if sample.pinchRatio <= 0.30 {
            if pinchStarted == nil { pinchStarted = sample.capturedAt }
            if sample.capturedAt - (pinchStarted ?? sample.capturedAt) >= 0.25 { pinching = true }
        } else if sample.pinchRatio > 0.42 {
            pinching = false; pinchStarted = nil
            return HandDecision(message: "Pinch released — stopped")
        } else if !pinching {
            pinchStarted = nil
        }
        guard pinching else { return HandDecision(message: "Hold the pinch briefly…") }
        let horizontal = sample.palmX - 0.5
        let steer = abs(horizontal) <= 0.08 ? 0 : max(-1, min(1, (abs(horizontal) - 0.08) / 0.27)) * (horizontal < 0 ? -1.0 : 1.0)
        return HandDecision(steering: steer * 0.32, forward: 0.60,
                            message: steer < -0.1 ? "Pinch held · steering left" : steer > 0.1 ? "Pinch held · steering right" : "Pinch held · forward")
    }
}
