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
