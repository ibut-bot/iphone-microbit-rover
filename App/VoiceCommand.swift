import Foundation
import CoreGraphics

// Pure policy shared by the recognizer, Bluetooth deadline and native tests.
enum VoiceDirection: String, CaseIterable {
    case forward, reverse, left, right, stop
    var vector: CGSize {
        switch self {
        case .forward: return CGSize(width: 0, height: -1)
        case .reverse: return CGSize(width: 0, height: 1)
        case .left: return CGSize(width: -1, height: 0)
        case .right: return CGSize(width: 1, height: 0)
        case .stop: return .zero
        }
    }
    var duration: TimeInterval {
        switch self { case .forward, .reverse: return 5; case .left, .right: return 1; case .stop: return 0 }
    }
}

struct VoiceCommand: Equatable {
    let direction: VoiceDirection
    let small: Bool
    var duration: TimeInterval { small ? min(direction.duration, direction == .left || direction == .right ? 0.5 : 1) : direction.duration }
    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }
    static func containsStop(_ text: String) -> Bool {
        !Set(words(text)).isDisjoint(with: ["stop", "halt", "freeze", "cancel"])
    }
    // A single explicit direction and wake prefix are mandatory, even for AI.
    static func candidate(_ text: String) -> VoiceCommand? {
        let tokens = words(text)
        guard tokens.first == "rover", tokens.count <= 18 else { return nil }
        let blocked: Set<String> = ["not", "don't", "dont", "never", "no", "without", "unless", "if", "then", "and", "or", "after", "before", "until", "seconds", "second", "minutes", "minute", "degrees", "degree", "metres", "meters", "feet", "fast", "faster", "full", "maximum"]
        guard Set(tokens).isDisjoint(with: blocked), !tokens.contains(where: { $0.contains(where: \.isNumber) }) else { return nil }
        let aliases: [VoiceDirection: Set<String>] = [.forward: ["forward", "forwards", "ahead"], .reverse: ["reverse", "back", "backward", "backwards"], .left: ["left"], .right: ["right"]]
        let directions = aliases.filter { !Set(tokens).isDisjoint(with: $0.value) }.map(\.key)
        guard directions.count == 1 else { return nil }
        return VoiceCommand(direction: directions[0], small: tokens.contains("little") || tokens.contains("slightly"))
    }
    static func isIncomplete(_ text: String) -> Bool {
        let tokens = words(text)
        let prefixWords: Set<String> = ["rover", "please", "go", "move", "turn", "rotate", "drive", "could", "you", "would", "can"]
        return tokens.first == "rover" && tokens.allSatisfy { prefixWords.contains($0) }
    }
    static func direct(_ text: String) -> VoiceCommand? {
        if containsStop(text) { return VoiceCommand(direction: .stop, small: false) }
        guard let candidate = candidate(text) else { return nil }
        let filler: Set<String> = ["rover", "please", "go", "move", "turn", "rotate", "drive", "slowly", "a", "little", "bit", "slightly", "up"]
        var tokens = words(text)
        // Polite imperative prefixes are ordinary commands, not AI capability questions.
        // Strip only this exact prefix; unrelated questions still fail the strict grammar.
        if tokens.count >= 3, tokens[0] == "rover",
           ["can", "could", "would", "will"].contains(tokens[1]), tokens[2] == "you" {
            tokens.removeSubrange(1...2)
        }
        let remaining = tokens.filter { !filler.contains($0) }
        let directions: Set<String> = ["forward", "forwards", "ahead", "reverse", "back", "backward", "backwards", "left", "right"]
        guard remaining.count == 1, directions.contains(remaining[0]) else { return nil }
        return candidate
    }
}

struct VoiceMotionGate {
    private(set) var command: VoiceCommand?
    private(set) var deadline: TimeInterval = 0
    mutating func start(_ command: VoiceCommand, now: TimeInterval, enabled: Bool) -> Bool {
        guard enabled, command.direction != .stop, now.isFinite else { return false }
        self.command = command
        deadline = now + command.duration
        return true
    }
    mutating func cancel() { command = nil; deadline = 0 }
    mutating func expire(now: TimeInterval) -> Bool {
        guard command != nil else { return false }
        guard now.isFinite, now < deadline else { cancel(); return true }
        return false
    }
}

/// Consume recognizer segments once, even when partial results repeat the full transcript.
struct VoiceTranscriptCursor {
    struct Segment { let text: String; let start: TimeInterval; let duration: TimeInterval }
    private(set) var consumedThrough: TimeInterval = -1
    func pending(_ segments: [Segment]) -> String {
        segments.filter { $0.start >= consumedThrough - 0.01 }.map(\.text).joined(separator: " ")
    }
    mutating func consume(_ segments: [Segment]) {
        guard let last = segments.last else { return }
        consumedThrough = max(consumedThrough, last.start + max(last.duration, 0.02))
    }
}

/// One fresh input may wait for ARM. Release/STOP discard it; acknowledgements cannot revive it.
struct PendingDriveInput {
    struct Input { let vector: CGSize; let voice: VoiceCommand?; let expires: TimeInterval }
    private(set) var input: Input?
    mutating func set(_ vector: CGSize, voice: VoiceCommand?, now: TimeInterval) {
        guard vector.width.isFinite, vector.height.isFinite, now.isFinite, vector != .zero else { clear(); return }
        input = Input(vector: vector, voice: voice, expires: now + (voice == nil ? 0.35 : 1))
    }
    mutating func clear() { input = nil }
    mutating func fresh(now: TimeInterval) -> Input? {
        guard let input, now.isFinite, now < input.expires else { clear(); return nil }
        return input
    }
    mutating func take(now: TimeInterval) -> Input? {
        let result = fresh(now: now); clear(); return result
    }
}
