import SwiftUI
import ReplayKit
import Photos

/// ReplayKit records the rendered app: both cameras, joystick, and visible controls.
/// Files are retained in Documents before attempting Photos, so a denied save is recoverable.
final class RoverRecording: NSObject, ObservableObject, RPScreenRecorderDelegate {
    @Published var recording = false
    @Published var busy = false
    @Published var status = ""
    @Published var savedURL: URL?
    @Published var recoveryPreview: RPPreviewViewController?
    @Published var showRecovery = false
    private var generation = 0
    private var starting = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let recorder = RPScreenRecorder.shared()

    override init() {
        super.init()
        recorder.delegate = self
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false // Our AVCaptureMultiCamSession owns both cameras.
    }
    func start() {
        guard !busy, !recording, recorder.isAvailable else {
            if !recorder.isAvailable { status = "Screen recording unavailable" }
            return
        }
        generation += 1
        let token = generation
        busy = true; starting = true; status = "Preparing recording…"
        // Ask before recording, so the permission dialog isn't part of the video.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generation == token else { self.starting = false; self.busy = false; return }
                self.recorder.startRecording { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.starting = false; self.busy = false
                        if let error { self.status = "Recording unavailable: \(error.localizedDescription)"; return }
                        self.recording = true; self.status = "Recording both cameras + joystick"
                        if self.generation != token { self.stop() }
                    }
                }
            }
        }
    }
    func stop() {
        generation += 1
        guard recording else {
            // Invalidates pending permission callbacks. A ReplayKit start in flight
            // detects this generation change and finalizes as soon as it completes.
            if starting { status = "Cancelling recording…" }
            return
        }
        recording = false; busy = true; status = "Saving video…"
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent("Rover-\(UUID().uuidString).mp4")
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save rover video") { [weak self] in
            self?.endBackgroundTask()
        }
        recorder.stopRecording(withOutput: url) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.busy = false; self.status = "Could not finish video: \(error.localizedDescription)"
                    self.endBackgroundTask(); return
                }
                self.savedURL = url
                let access = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                guard access == .authorized || access == .limited else {
                    self.busy = false; self.status = "Video saved in app · use Share to save to Files or Photos"
                    self.endBackgroundTask(); return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        self.busy = false
                        self.status = success ? "Saved to Photos" : "Photos save failed · video retained in app: \(error?.localizedDescription ?? "Use Share")"
                        self.endBackgroundTask()
                    }
                }
            }
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    func screenRecorder(_ screenRecorder: RPScreenRecorder, didStopRecordingWith previewViewController: RPPreviewViewController?, error: Error?) {
        DispatchQueue.main.async {
            self.recording = false; self.starting = false; self.busy = false; self.generation += 1
            self.status = "Recording interrupted: \(error?.localizedDescription ?? "Stopped by iOS")"
            if let previewViewController { self.recoveryPreview = previewViewController; self.showRecovery = true }
            self.endBackgroundTask()
        }
    }
}

struct RecordingRecoveryView: UIViewControllerRepresentable {
    let controller: RPPreviewViewController
    func makeUIViewController(context: Context) -> RPPreviewViewController { controller }
    func updateUIViewController(_ uiViewController: RPPreviewViewController, context: Context) {}
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
                        Spacer()
                        Button {
                            // A recording permission prompt can interrupt tracking: stop/disarm first.
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
