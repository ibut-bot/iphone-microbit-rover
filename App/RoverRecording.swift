import SwiftUI
import AVFoundation
import Photos

/// Writes camera frames and the joystick directly; no screen-recording service/export step.
final class RoverRecording: ObservableObject {
    @Published var recording = false
    @Published var busy = false
    @Published var status = ""
    @Published var savedURL: URL?
    @Published var clips: [URL] = []
    @Published var showLibrary = false
    @Published var frameCount = 0
    private let queue = DispatchQueue(label: "rover.video-writer", qos: .userInitiated)
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var firstTime: TimeInterval?
    private var count = 0
    private var pendingFrame = false // Main queue: one frame in flight, no backlog.
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() { refreshClips() }
    func refreshClips() {
        clips = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        savedURL = clips.first
    }
    func start() {
        guard !busy, !recording else { return }
        frameCount = 0; status = "Recording · waiting for camera frames"; recording = true
        // Configuration is deferred to the first frame, using its actual portrait aspect.
        queue.async { self.writer = nil; self.input = nil; self.adaptor = nil; self.firstTime = nil; self.count = 0; self.outputURL = nil }
    }
    func append(front: UIImage?, rear: UIImage?, decision: HandDecision, landmarks: [CGPoint]) {
        guard recording, !pendingFrame, let front = front?.cgImage, let rear = rear?.cgImage else { return }
        pendingFrame = true
        let timestamp = ProcessInfo.processInfo.systemUptime
        queue.async {
            defer { DispatchQueue.main.async { self.pendingFrame = false } }
            do {
                if self.writer == nil { try self.configure(front: front) }
                guard let writer = self.writer, let input = self.input, let adaptor = self.adaptor else { return }
                guard writer.status == .writing else { throw writer.error ?? self.failure("Video writer stopped") }
                guard input.isReadyForMoreMediaData else { return }
                guard let pool = adaptor.pixelBufferPool else { throw self.failure("Video buffer unavailable") }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw self.failure("Could not allocate video frame") }
                try VideoComposite.draw(front: front, rear: rear, decision: decision, landmarks: landmarks, into: buffer)
                if self.firstTime == nil { self.firstTime = timestamp }
                let time = CMTime(seconds: timestamp - (self.firstTime ?? timestamp), preferredTimescale: 600)
                guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? self.failure("Could not write video frame") }
                self.count += 1
                let frames = self.count
                DispatchQueue.main.async {
                    self.frameCount = frames
                    if self.recording { self.status = "Recording · \(frames) frames written" }
                }
            } catch {
                self.writer?.cancelWriting()
                if let url = self.outputURL { try? FileManager.default.removeItem(at: url) }
                self.writer = nil
                DispatchQueue.main.async {
                    self.recording = false; self.busy = false
                    self.status = "Recording failed: \(error.localizedDescription)"
                    self.endBackgroundTask()
                }
            }
        }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "RoverVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func configure(front: CGImage) throws {
        let width = 720
        let height = min(1920, max(2, Int((Double(front.height) / Double(front.width) * Double(width)) / 2) * 2))
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("Rover-\(stamp)-\(UUID().uuidString.prefix(6)).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000, AVVideoExpectedSourceFrameRateKey: 15]])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw failure("Video format unsupported") }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.startWriting() else { throw writer.error ?? failure("Could not start video file") }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer; self.input = input; self.adaptor = adaptor; outputURL = url
    }
    func stop() {
        guard recording else { return }
        recording = false; busy = true; status = "Finishing video…"
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save rover video") { [weak self] in self?.endBackgroundTask() }
        queue.async {
            guard let writer = self.writer, let input = self.input, let url = self.outputURL, self.count > 0 else {
                self.writer?.cancelWriting()
                if let url = self.outputURL { try? FileManager.default.removeItem(at: url) }
                DispatchQueue.main.async { self.busy = false; self.status = "No camera frames recorded. Wait for both previews before recording."; self.endBackgroundTask() }
                return
            }
            input.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    guard writer.status == .completed else {
                        self.busy = false; self.status = "Video could not finish: \(writer.error?.localizedDescription ?? "Unknown error")"; self.endBackgroundTask(); return
                    }
                    self.savedURL = url; self.refreshClips()
                    self.saveToPhotos(url)
                }
            }
        }
    }
    func saveToPhotos(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { status = "Video file is missing"; busy = false; return }
        busy = true; status = "Video saved on iPhone · saving to Photos…"
        let save: (PHAuthorizationStatus) -> Void = { access in
            guard access == .authorized || access == .limited else {
                DispatchQueue.main.async {
                    self.busy = false; self.status = "Saved in Files → Microbit Link. Photos access is off; use Share or allow Photos in Settings."
                    self.showLibrary = UIApplication.shared.applicationState == .active; self.endBackgroundTask()
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    self.busy = false
                    self.status = success ? "Video saved to Photos and Files" : "Saved in Files; Photos error: \(error?.localizedDescription ?? "Unknown error")"
                    self.showLibrary = UIApplication.shared.applicationState == .active; self.endBackgroundTask()
                }
            }
        }
        let access = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if access == .notDetermined && UIApplication.shared.applicationState == .active {
            PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: save)
        } else { save(access) }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}

/// Compose a portrait movie from the exact front/rear camera frames and current joystick state.
enum VideoComposite {
    static func draw(front: CGImage, rear: CGImage, decision: HandDecision, landmarks: [CGPoint], into buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw NSError(domain: "RoverVideo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not render video"])
        }
        let w = CGFloat(width), h = CGFloat(height)
        context.translateBy(x: 0, y: h); context.scaleBy(x: 1, y: -1)
        func image(_ image: CGImage, in rect: CGRect) {
            context.saveGState(); context.clip(to: rect)
            let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
            let dw = CGFloat(image.width) * scale, dh = CGFloat(image.height) * scale
            context.translateBy(x: rect.midX - dw / 2, y: rect.midY + dh / 2)
            context.scaleBy(x: 1, y: -1); context.draw(image, in: CGRect(x: 0, y: 0, width: dw, height: dh)); context.restoreGState()
        }
        image(front, in: CGRect(x: 0, y: 0, width: w, height: h))
        let centre = CGPoint(x: w / 2, y: h / 2), radius = w * HandDriveGate.radius
        let ring = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        let tint = decision.held ? UIColor.systemMint : UIColor.white
        context.setFillColor(tint.withAlphaComponent(decision.held ? 0.18 : 0.10).cgColor); context.fillEllipse(in: ring)
        context.setStrokeColor(tint.withAlphaComponent(decision.held ? 1 : 0.65).cgColor); context.setLineWidth(decision.held ? 5 : 3); context.strokeEllipse(in: ring)
        context.setLineWidth(1); context.move(to: CGPoint(x: centre.x - radius, y: centre.y)); context.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
        context.move(to: CGPoint(x: centre.x, y: centre.y - radius)); context.addLine(to: CGPoint(x: centre.x, y: centre.y + radius)); context.strokePath()
        context.setLineDash(phase: 0, lengths: [6, 6]); context.strokeEllipse(in: ring.insetBy(dx: radius * (1 - HandDriveGate.deadzone), dy: radius * (1 - HandDriveGate.deadzone))); context.setLineDash(phase: 0, lengths: [])
        let knob = CGRect(x: centre.x + decision.stickX * radius - 32, y: centre.y - decision.stickY * radius - 32, width: 64, height: 64)
        context.setFillColor(tint.withAlphaComponent(0.65).cgColor); context.fillEllipse(in: knob)
        context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(2); context.strokeEllipse(in: knob)
        context.setFillColor((decision.held ? UIColor.systemMint : UIColor.systemYellow).cgColor)
        for p in landmarks { context.fillEllipse(in: CGRect(x: p.x * w - 3, y: p.y * h - 3, width: 6, height: 6)) }
        let inset = CGRect(x: w * 0.67, y: h - w * 0.43, width: w * 0.30, height: w * 0.40)
        context.saveGState(); context.addPath(CGPath(roundedRect: inset, cornerWidth: 18, cornerHeight: 18, transform: nil)); context.clip(); image(rear, in: inset); context.restoreGState()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor); context.addPath(CGPath(roundedRect: inset, cornerWidth: 18, cornerHeight: 18, transform: nil)); context.strokePath()
        // UIKit text drawing uses this explicit bitmap context; no screen/UI capture occurs.
        UIGraphicsPushContext(context)
        let style: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white, .strokeColor: UIColor.black, .strokeWidth: -3]
        (decision.held ? "JOYSTICK ACTIVE" : "PINCH TO GRAB" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: style)
        ("ROVER · REAR" as NSString).draw(at: CGPoint(x: inset.minX + 8, y: inset.minY + 8), withAttributes: style)
        UIGraphicsPopContext()
    }
}

struct RecordingLibraryView: View {
    @ObservedObject var recording: RoverRecording
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text(recording.status.isEmpty ? "Videos stay on your iPhone." : recording.status) }
                if recording.clips.isEmpty { Text("No completed recordings yet") }
                ForEach(recording.clips, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(url.lastPathComponent).font(.caption).textSelection(.enabled)
                        HStack {
                            ShareLink(item: url) { Label("Share / Save", systemImage: "square.and.arrow.up") }
                            Spacer()
                            Button("Save to Photos") { recording.saveToPhotos(url) }.disabled(recording.busy)
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 6)
                }
                Section { Text("Also in Files → On My iPhone → Microbit Link. Share lets you preview or export a video. Saving to Photos again creates another copy.") }
            }.navigationTitle("Recordings")
                .toolbar { Button("Done") { dismiss() } }
                .onAppear { recording.refreshClips() }
        }
    }
}
struct ImmersiveHandView: View {
    @ObservedObject var camera: HandCamera
    @ObservedObject var link: BluetoothLink
    @ObservedObject var recording: RoverRecording
    var exit: () -> Void
    var guide: () -> Void
    var enable: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HandCameraView(camera: camera, decision: link.handDecision, height: geo.size.height, minimal: true)
                VStack {
                    HStack(spacing: 10) {
                        Button(action: exit) { Label("Exit", systemImage: "xmark") }
                        Button(action: guide) { Image(systemName: "hand.raised.fill") }.accessibilityLabel("Gesture guide")
                        Button { link.emergencyStop(); recording.stop(); recording.showLibrary = true } label: { Image(systemName: "film.stack") }.accessibilityLabel("Saved recordings")
                        Spacer()
                        Button {
                            // Changing recording state stops/disarms the rover before the save flow.
                            link.emergencyStop()
                            if recording.recording { recording.stop() } else { recording.start() }
                        } label: {
                            Label(recording.recording ? "Stop recording" : "Record", systemImage: recording.recording ? "stop.circle.fill" : "record.circle")
                        }.tint(recording.recording ? .red : .white)
                            .disabled(recording.busy || (!recording.recording && (!camera.running || camera.rearImage == nil)))
                    }.buttonStyle(.bordered).background(.black.opacity(0.35), in: Capsule())
                    if recording.recording || recording.busy {
                        Text(recording.status).font(.caption.bold()).padding(6).background(.black.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(link.handDecision.message).font(.subheadline.bold())
                            if !link.armed { Text(link.status).font(.caption).lineLimit(2) }
                            if !recording.recording && !recording.busy && !recording.status.isEmpty {
                                Text(recording.status).font(.caption).lineLimit(3)
                                if let url = recording.savedURL { ShareLink(item: url) { Label("Share video", systemImage: "square.and.arrow.up") } }
                            }
                            if link.armed {
                                Button { link.emergencyStop() } label: { Label("STOP", systemImage: "stop.fill").bold() }
                                    .buttonStyle(.borderedProminent).tint(.red)
                            } else {
                                Button("Enable driving", action: enable).buttonStyle(.borderedProminent)
                                    .disabled(!link.ready || !link.roverCompatible || !camera.running || recording.busy)
                            }
                        }.padding(10).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                        Spacer(minLength: 0)
                        ZStack(alignment: .topLeading) {
                            Color.black
                            if let rear = camera.rearImage {
                                Image(uiImage: rear).resizable().scaledToFill()
                            } else { Text(camera.rearMessage).font(.caption).padding(8).padding(.top, 24) }
                            Text("ROVER · REAR").font(.caption2.bold()).padding(5).background(.black.opacity(0.6))
                        }.frame(width: geo.size.width * 0.30, height: geo.size.width * 0.40)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.7), lineWidth: 1))
                    }
                }.padding(12).foregroundStyle(.white)
            }.background(.black)
        }
    }
}

#if targetEnvironment(simulator)
extension RoverRecording {
    /// Device-free integration check of the real compositor, writer, finalization and save flow.
    func runSimulatorSmokeTest() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        func fixture(_ color: UIColor, label: String) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 360, height: 720), format: format).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 360, height: 720))
                UIColor.white.setFill(); context.fill(CGRect(x: 20, y: 70, width: 100, height: 80))
                (label as NSString).draw(at: CGPoint(x: 20, y: 170), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white])
            }
        }
        let front = fixture(.systemBlue, label: "FRONT TOP")
        let rear = fixture(.systemRed, label: "REAR TOP")
        start()
        var frames = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            frames += 1
            self.append(front: front, rear: rear, decision: HandDecision(held: true, stickX: sin(Double(frames) / 5) * 0.8, stickY: 0.3, steering: 0.4, forward: 0.2, message: "Test"), landmarks: [])
            if frames == 30 { timer.invalidate(); self.stop() }
        }
    }
}
#endif
