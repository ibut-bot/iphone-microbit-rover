import Foundation
import CoreGraphics

/// Coordinates refer to the same upright, mirrored image shown in the preview.
struct HandSample {
    let pinchX: Double
    let pinchY: Double // Vision coordinates: up is positive.
    let imageAspect: Double // Width / height, for equal horizontal and vertical travel.
    let pinchRatio: Double // Tip distance divided by estimated index-finger length.
    let capturedAt: TimeInterval
}

struct HandDecision {
    var held = false
    var stickX = 0.0
    var stickY = 0.0
    var steering = 0.0
    var forward = 0.0
    var message: String
    var moving: Bool { hypot(steering, forward) > 0 }
}

struct HandDriveGate {
    static let maxFrameAge: TimeInterval = 0.30
    static let radius = 0.30 // Fraction of image width.
    static let deadzone = 0.28
    private var sawOpenHand = false
    private var pinchStarted: TimeInterval?
    private var pinching = false
    private var lastSampleAt: TimeInterval?

    mutating func reset() {
        sawOpenHand = false; pinchStarted = nil; pinching = false
        lastSampleAt = nil
    }
    mutating func evaluate(_ sample: HandSample?, now: TimeInterval, enabled: Bool) -> HandDecision {
        guard enabled else {
            reset()
            return HandDecision(message: "Enable driving · separate thumb and index")
        }
        guard let sample else {
            // Stop immediately, but don't require another open-hand ritual for one dropped frame.
            // Reacquisition still needs a new pinch dwell; a sustained loss fully resets the gate.
            pinching = false; pinchStarted = nil
            if let last = lastSampleAt, now - last > 0.6 { reset() }
            return HandDecision(message: "Hand not clear — stopped")
        }
        guard sample.pinchX.isFinite, sample.pinchY.isFinite, sample.imageAspect.isFinite, sample.pinchRatio.isFinite,
              sample.pinchY >= 0, sample.pinchY <= 1, sample.imageAspect > 0,
              sample.pinchX >= 0, sample.pinchX <= 1, sample.pinchRatio >= 0,
              now >= sample.capturedAt, now - sample.capturedAt <= Self.maxFrameAge else {
            reset()
            return HandDecision(message: "Tracking delayed — stopped")
        }
        if let last = lastSampleAt {
            if sample.capturedAt <= last || sample.capturedAt - last > 0.6 { reset() }
            else if sample.capturedAt - last > Self.maxFrameAge { pinching = false; pinchStarted = nil }
        }
        lastSampleAt = sample.capturedAt
        if sample.pinchRatio >= 0.85 {
            sawOpenHand = true; pinchStarted = nil; pinching = false
            return HandDecision(message: "Pinch the centre to grab the joystick")
        }
        guard sawOpenHand else { return HandDecision(message: "Open thumb and index finger first") }
        let x = (sample.pinchX - 0.5) / Self.radius
        let y = (sample.pinchY - 0.5) / sample.imageAspect / Self.radius
        let magnitude = hypot(x, y)
        if !pinching && magnitude > Self.deadzone {
            pinchStarted = nil
            return HandDecision(message: "Bring the pinch into the centre circle")
        }
        if sample.pinchRatio <= 0.42 {
            if pinchStarted == nil { pinchStarted = sample.capturedAt }
            if sample.capturedAt - (pinchStarted ?? sample.capturedAt) >= 0.15 { pinching = true }
        } else if sample.pinchRatio > 0.70 {
            pinching = false; pinchStarted = nil
            return HandDecision(message: "Pinch released — stopped")
        } else if !pinching { pinchStarted = nil }
        guard pinching else { return HandDecision(message: "Hold pinch briefly…") }

        let divisor = max(1, magnitude)
        let power = magnitude <= Self.deadzone ? 0 : min(1, (magnitude - Self.deadzone) / (1 - Self.deadzone)) * 0.85
        let steering = magnitude > 0 ? x / magnitude * power : 0
        let forward = magnitude > 0 ? y / magnitude * power : 0
        let direction = power == 0 ? "CENTRED · stopped" : abs(y) >= abs(x) ? (y > 0 ? "FORWARD" : "REVERSE") : (x < 0 ? "LEFT" : "RIGHT")
        return HandDecision(held: true, stickX: x / divisor, stickY: y / divisor,
                            steering: steering, forward: forward,
                            message: direction + " · release pinch to stop")
    }
}

/// Both Vision and the displayed image use this same centred crop.
enum CameraFraming {
    static func crop(source: CGSize, aspect: CGFloat) -> CGRect {
        guard source.width > 0, source.height > 0, aspect.isFinite, aspect > 0 else { return .zero }
        let width = min(source.width, source.height * aspect)
        let height = min(source.height, source.width / aspect)
        return CGRect(x: (source.width - width) / 2, y: (source.height - height) / 2, width: width, height: height)
    }
}
