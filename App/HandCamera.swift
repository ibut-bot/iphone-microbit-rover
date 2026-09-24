import SwiftUI
import AVFoundation
import Vision
import CoreImage

final class HandCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var image: UIImage?
    @Published var rearImage: UIImage?
    @Published var rearMessage = "Starting rear camera…"
    @Published var landmarks: [CGPoint] = []
    @Published var message = "Front camera stays on this phone"
    @Published var running = false
    @Published var denied = false
    var onSample: ((HandSample?) -> Void)?

    private let session: AVCaptureSession = AVCaptureMultiCamSession.isMultiCamSupported ? AVCaptureMultiCamSession() : AVCaptureSession()
    private var rearOutput: AVCaptureVideoDataOutput?
    private var rearLastProcessed: TimeInterval = 0
    private var viewportAspect: CGFloat = 0.5
    func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        captureQueue.async { [weak self] in self?.viewportAspect = size.width / size.height }
    }
    private let captureQueue = DispatchQueue(label: "rover.hand-camera", qos: .userInitiated)
    private let context = CIContext()
    private let request = VNDetectHumanHandPoseRequest()
    private var rotationCoordinators: [AVCaptureDevice.RotationCoordinator] = []
    private var rotationObservations: [NSKeyValueObservation] = []
    private var configured = false // Capture queue only.
    private var captureGeneration = 0 // Capture queue only.
    private var generation = 0 // Main queue only.
    private var requested = false // Main queue only.
    private var lastProcessed: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        request.maximumHandCount = 2 // More than one visible hand is ambiguous: stop.
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                self?.stop()
                self?.message = "Camera interrupted — tap Start camera"
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        guard !requested else { return }
        requested = true; generation += 1
        let token = generation
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: begin(token)
        case .notDetermined:
            message = "Allow camera access to recognise your hand"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.generation == token, self.requested else { return }
                    if granted { self.begin(token) } else { self.permissionDenied() }
                }
            }
        default: permissionDenied()
        }
    }
    private func permissionDenied() {
        requested = false; running = false; denied = true
        message = "Camera access is off. Enable it in Settings."
        onSample?(nil)
    }
    func stop() {
        requested = false; generation += 1
        running = false; image = nil; rearImage = nil; landmarks = []
        onSample?(nil)
        captureQueue.async { [weak self] in self?.session.stopRunning() }
    }
    private func begin(_ token: Int) {
        denied = false; message = "Starting front camera…"
        captureQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured { try self.configure() }
                self.captureGeneration = token; self.lastProcessed = 0
                self.session.startRunning()
                DispatchQueue.main.async {
                    guard self.generation == token, self.requested else { return }
                    self.running = self.session.isRunning
                    self.message = self.running ? "Show your thumb and index finger" : "Camera unavailable — try again"
                    if !self.running { self.requested = false; self.onSample?(nil) }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.requested = false; self.running = false
                    self.message = "Camera unavailable: \(error.localizedDescription)"
                    self.rearMessage = "Rear camera unavailable"
                    self.onSample?(nil)
                }
            }
        }
    }
    private func cameraError(_ message: String) -> NSError {
        NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Clear a partial setup before retrying a failed configuration.
        for connection in session.connections { session.removeConnection(connection) }
        for output in session.outputs { session.removeOutput(output) }
        for input in session.inputs { session.removeInput(input) }
        rotationObservations.removeAll(); rotationCoordinators.removeAll(); rearOutput = nil
        if !(session is AVCaptureMultiCamSession) { session.sessionPreset = .vga640x480 }
        _ = try addCamera(position: .front)
        if session is AVCaptureMultiCamSession {
            do {
                rearOutput = try addCamera(position: .back)
                guard session.hardwareCost <= 1 else { throw cameraError("Dual camera exceeds device resources") }
                DispatchQueue.main.async { self.rearMessage = "Rear camera" }
            } catch {
                // A partially configured rear camera is removed without breaking front tracking.
                for output in session.outputs.dropFirst() { session.removeOutput(output) }
                for input in session.inputs.dropFirst() { session.removeInput(input) }
                rearOutput = nil
                DispatchQueue.main.async { self.rearMessage = "Rear camera unavailable: \(error.localizedDescription)" }
            }
        } else {
            DispatchQueue.main.async { self.rearMessage = "Dual cameras unsupported on this device" }
        }
        configured = true
    }
    private func addCamera(position: AVCaptureDevice.Position) throws -> AVCaptureVideoDataOutput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw cameraError("Camera not found")
        }
        let input = try AVCaptureDeviceInput(device: device)
        if session is AVCaptureMultiCamSession {
            let formats = device.formats.filter {
                let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return $0.isMultiCamSupported && d.width >= 640 && d.height >= 480 &&
                    $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 }
            }.sorted {
                let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return Int(a.width) * Int(a.height) < Int(b.width) * Int(b.height)
            }
            guard let format = formats.first else { throw cameraError("No dual-camera format") }
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            device.unlockForConfiguration()
            input.videoMinFrameDurationOverride = CMTime(value: 1, timescale: 15)
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddInput(input) else { throw cameraError("Cannot add camera input") }
        session.addInputWithNoConnections(input)
        guard session.canAddOutput(output) else { throw cameraError("Cannot add camera output") }
        session.addOutputWithNoConnections(output)
        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: position).first else {
            throw cameraError("Missing camera port")
        }
        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else { throw cameraError("Cannot connect camera") }
        session.addConnection(connection)
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinators.append(coordinator)
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        rotationObservations.append(coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self, weak connection] _, change in
            guard let self, let angle = change.newValue else { return }
            self.captureQueue.async {
                guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        })
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
        return output
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if output === rearOutput {
            guard timestamp - rearLastProcessed >= 1.0 / 16 else { return }
            rearLastProcessed = timestamp
            let token = captureGeneration
            let frame = CIImage(cvPixelBuffer: pixelBuffer)
            let cgImage = context.createCGImage(frame, from: frame.extent)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requested, self.generation == token,
                      ProcessInfo.processInfo.systemUptime - timestamp < 0.5 else { return }
                self.rearImage = cgImage.map { UIImage(cgImage: $0) }
            }
            return
        }
        guard timestamp - lastProcessed >= 1.0 / 16 else { return }
        lastProcessed = timestamp
        let token = captureGeneration
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let crop = CameraFraming.crop(source: source.extent.size, aspect: viewportAspect)
        let frame = source.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let cgImage = context.createCGImage(frame, from: frame.extent)
        var sample: HandSample?
        var dots: [CGPoint] = []
        var status = "Show your thumb and index finger"
        do {
            try VNImageRequestHandler(ciImage: frame, orientation: .up).perform([request])
            let hands = request.results ?? []
            if hands.count > 1 { status = "Use only one hand — stopped" }
            if hands.count == 1, let hand = hands.first {
                let points = try hand.recognizedPoints(.all)
                let relevant: [VNHumanHandPoseObservation.JointName] = [.thumbCMC, .thumbMP, .thumbIP, .thumbTip, .indexMCP, .indexPIP, .indexDIP, .indexTip]
                dots = relevant.compactMap { points[$0] }.filter { $0.confidence >= 0.45 }.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
                func point(_ key: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                    guard let p = points[key], p.confidence >= 0.45 else { return nil }
                    return p.location
                }
                if let thumb = point(.thumbTip), let index = point(.indexTip),
                   let indexBase = point(.indexMCP), let indexKnuckle = point(.indexPIP) {
                    // Distances use pixels, not distorted normalized coordinates on a portrait frame.
                    func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
                        hypot((a.x - b.x) * frame.extent.width, (a.y - b.y) * frame.extent.height)
                    }
                    // Use only the index finger's proximal segment to estimate scale.
                    // Unlike base-to-tip distance, this does not collapse when the index curls.
                    let fingerSize = distance(indexBase, indexKnuckle) * 2.2
                    if fingerSize > frame.extent.height * 0.045 {
                        sample = HandSample(pinchX: (thumb.x + index.x) / 2,
                                            pinchY: (thumb.y + index.y) / 2,
                                            imageAspect: frame.extent.width / frame.extent.height,
                                            pinchRatio: distance(thumb, index) / fingerSize,
                                            capturedAt: timestamp)
                        status = "Thumb + index tracked"
                    } else { status = "Bring your hand closer — stopped" }
                } else { status = "Show thumb/index tips and index knuckle — stopped" }
            }
        } catch { status = "Hand tracking unavailable — stopped" }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.requested, self.generation == token else { return }
            guard ProcessInfo.processInfo.systemUptime - timestamp <= HandDriveGate.maxFrameAge else {
                self.landmarks = []; self.message = "Camera frames delayed — stopped"; self.onSample?(nil); return
            }
            self.image = cgImage.map { UIImage(cgImage: $0) }
            self.landmarks = dots; self.message = status
            self.onSample?(sample)
        }
    }
}

struct HandCameraView: View {
    @ObservedObject var camera: HandCamera
    let decision: HandDecision
    var height: CGFloat = 285
    var minimal = false
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Color.black)
                if let image = camera.image {
                    GeometryReader { geo in
                        let scale = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        ZStack {
                            Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                            CameraJoystick(decision: decision)
                                .frame(width: size.width * HandDriveGate.radius * 2,
                                       height: size.width * HandDriveGate.radius * 2)
                            ForEach(Array(camera.landmarks.enumerated()), id: \.offset) { _, point in
                                Circle().fill(decision.moving ? Color.mint : Color.yellow)
                                    .frame(width: 5, height: 5).position(x: point.x * size.width, y: point.y * size.height)
                            }
                        }.frame(width: size.width, height: size.height).position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.fingers.spread.fill").font(.largeTitle)
                        Text(camera.message).font(.subheadline).multilineTextAlignment(.center)
                        if camera.denied {
                            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        } else { Button("Start camera") { camera.start() } }
                    }.foregroundStyle(.white).padding()
                }
                VStack(spacing: 8) {
                    if !minimal { Text(decision.held ? "JOYSTICK ACTIVE · RELEASE TO STOP" : "PINCH CENTRE TO GRAB")
                        .font(.caption.bold()).padding(10).background(.black.opacity(0.55), in: Capsule()) }
                    Spacer()
                    if !minimal { Text(decision.message).font(.headline).multilineTextAlignment(.center)
                    Text(camera.message).font(.caption).multilineTextAlignment(.center) }
                }.foregroundStyle(.white).padding(14)
                    .background(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                            .allowsHitTesting(false)
                    }.allowsHitTesting(false)
            }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: minimal ? 0 : 22))
                .background(GeometryReader { geo in Color.clear
                    .onAppear { camera.setViewport(geo.size) }
                    .onChange(of: geo.size) { _, size in camera.setViewport(size) }
                })
        }
    }
}

/// Shares its radius, deadzone and mirrored coordinates with the actual drive gate.
struct CameraJoystick: View {
    let decision: HandDecision
    var body: some View {
        GeometryReader { geo in
            let radius = geo.size.width / 2
            ZStack {
                Circle().fill(decision.held ? Color.mint.opacity(0.18) : Color.white.opacity(0.10))
                Circle().stroke(decision.held ? Color.mint : Color.white.opacity(0.65), lineWidth: decision.held ? 3 : 2)
                    .shadow(color: decision.held ? .mint.opacity(0.7) : .clear, radius: 10)
                Rectangle().fill(.white.opacity(0.22)).frame(width: 1)
                Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
                Circle().stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: geo.size.width * HandDriveGate.deadzone, height: geo.size.width * HandDriveGate.deadzone)
                Image(systemName: "arrow.up").offset(y: -radius + 18)
                Image(systemName: "arrow.down").offset(y: radius - 18)
                Image(systemName: "arrow.left").offset(x: -radius + 18)
                Image(systemName: "arrow.right").offset(x: radius - 18)
                Circle().fill(decision.held ? Color.mint.opacity(0.65) : Color.white.opacity(0.3))
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                    .frame(width: 42, height: 42)
                    .offset(x: decision.stickX * radius, y: -decision.stickY * radius)
            }.foregroundStyle(.white).font(.headline)
        }.allowsHitTesting(false)
            .accessibilityLabel(decision.held ? "Joystick grabbed" : "Pinch inside centre circle to grab joystick")
    }
}
