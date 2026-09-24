import Foundation
import AVFoundation
import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let duration = try await asset.load(.duration)
let tracks = try await asset.loadTracks(withMediaType: .video)
let size = try await tracks[0].load(.naturalSize)
print("duration=\(duration.seconds), size=\(size)")
assert(duration.seconds > 2 && size.width == 720 && size.height == 1440)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
let (image, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
let bitmap = NSBitmapImageRep(cgImage: image)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))

let audioTracks = try await asset.loadTracks(withMediaType: .audio)
assert(audioTracks.count == 1, "Expected one audio track")
let audioRange = try await audioTracks[0].load(.timeRange)
assert(audioRange.start.seconds < 0.3 && audioRange.duration.seconds > 2)
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: audioTracks[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
reader.add(output)
assert(reader.startReading())
var maximum: Int16 = 0
while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
    var samples = [Int16](repeating: 0, count: CMBlockBufferGetDataLength(block) / 2)
    let byteCount = samples.count * 2
    _ = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: $0.baseAddress!) }
    maximum = max(maximum, samples.max() ?? 0)
}
assert(maximum > 1000, "Audio must contain audible signal")
print("PASS: one decoded audio track, aligned start, peak=\(maximum)")
