import SwiftUI
import AVFoundation
import Vision
import CoreImage

final class HandCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var image: UIImage?
    @Published var landmarks: [CGPoint] = []
    @Published var message = "Front camera stays on this phone"
    @Published var running = false
    @Published var denied = false
    var onSample: ((HandSample?) -> Void)?

    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "rover.hand-camera", qos: .userInitiated)
    private let context = CIContext()
    private let request = VNDetectHumanHandPoseRequest()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
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
        running = false; image = nil; landmarks = []
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
                    self.message = self.running ? "Show one hand, palm facing the camera" : "Camera unavailable — try again"
                    if !self.running { self.requested = false; self.onSample?(nil) }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.requested = false; self.running = false
                    self.message = "Camera unavailable: \(error.localizedDescription)"
                    self.onSample?(nil)
                }
            }
        }
    }
    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No front camera on this device"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw NSError(domain: "Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to configure camera"])
        }
        session.addInput(input); session.addOutput(output)
        if let connection = output.connection(with: .video) {
            // Sensor orientation differs by camera (including newer front cameras).
            // Rotate the actual buffers so the preview and Vision share upright coordinates.
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationCoordinator = coordinator
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self, weak connection] _, change in
                guard let self, let angle = change.newValue else { return }
                self.captureQueue.async {
                    guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
                    connection.videoRotationAngle = angle
                }
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        configured = true
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard timestamp - lastProcessed >= 1.0 / 15, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessed = timestamp
        let token = captureGeneration
        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        let cgImage = context.createCGImage(frame, from: frame.extent)
        var sample: HandSample?
        var dots: [CGPoint] = []
        var status = "Show one hand, palm facing the camera"
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
            let hands = request.results ?? []
            if hands.count > 1 { status = "Use only one hand — stopped" }
            if hands.count == 1, let hand = hands.first {
                let points = try hand.recognizedPoints(.all)
                dots = points.values.filter { $0.confidence >= 0.6 }.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
                func point(_ key: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                    guard let p = points[key], p.confidence >= 0.6 else { return nil }
                    return p.location
                }
                if let wrist = point(.wrist), let thumb = point(.thumbTip), let index = point(.indexTip),
                   let indexBase = point(.indexMCP), let littleBase = point(.littleMCP), let middleBase = point(.middleMCP) {
                    // Distances use pixels, not distorted normalized coordinates on a portrait frame.
                    func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
                        hypot((a.x - b.x) * frame.extent.width, (a.y - b.y) * frame.extent.height)
                    }
                    let palmWidth = distance(indexBase, littleBase)
                    var extended = 0
                    let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [(.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP)]
                    for (tip, pip) in fingers {
                        if let t = point(tip), let p = point(pip), distance(t, wrist) > distance(p, wrist) * 1.12 { extended += 1 }
                    }
                    if palmWidth > frame.extent.width * 0.055 {
                        sample = HandSample(palmX: (wrist.x + middleBase.x) / 2,
                                            pinchRatio: distance(thumb, index) / palmWidth,
                                            otherFingersExtended: extended >= 2, capturedAt: timestamp)
                        status = "Hand tracked · processing on your iPhone"
                    } else { status = "Bring your hand closer — stopped" }
                } else { status = "Show your whole hand in good light — stopped" }
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
                            Path { path in
                                for fraction in [0.42, 0.58] {
                                    path.move(to: CGPoint(x: size.width * fraction, y: 0))
                                    path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                                }
                            }.stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
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
                VStack { Spacer(); Text("LEFT         CENTRE         RIGHT").font(.caption2.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.6), in: Capsule()).padding(10) }
            }.frame(height: 285).clipShape(RoundedRectangle(cornerRadius: 22))
            Label(decision.message, systemImage: decision.moving ? "arrow.up.circle.fill" : "hand.raised.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(decision.moving ? .green : .primary)
            Text(camera.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}
