import SwiftUI
import SceneKit
import simd

enum GestureLesson: Int, CaseIterable, Identifiable {
    case forward, left, right, stop
    var id: Int { rawValue }
    var title: String {
        switch self { case .forward: return "Pinch to move"; case .left: return "Steer left"; case .right: return "Steer right"; case .stop: return "Open to stop" }
    }
    var symbol: String {
        switch self { case .forward: return "arrow.up"; case .left: return "arrow.turn.up.left"; case .right: return "arrow.turn.up.right"; case .stop: return "stop.fill" }
    }
    var instruction: String {
        switch self {
        case .forward: return "First separate your thumb and index finger. Touch thumb and index finger together and hold briefly. Keep the pinch relaxed; the other fingers can rest naturally."
        case .left: return "Keep the pinch held and move your hand to the LEFT side of the camera preview. The left wheel stops and the right wheel drives the turn."
        case .right: return "Keep the pinch held and move your hand to the RIGHT side of the camera preview. The right wheel stops and the left wheel drives the turn."
        case .stop: return "Separate thumb and index finger to stop. If your hand leaves the frame, movement also stops. Tap STOP to disable driving completely."
        }
    }
}

/// Procedural articulated 3D hand; no remote assets or camera recordings.
final class DemoHand {
    let scene = SCNScene()
    let root = SCNNode()
    private var joints: [[SCNNode]] = []
    private var bones: [[SCNNode]] = []
    private let glow = SCNNode()

    init() {
        scene.background.contents = UIColor(red: 0.045, green: 0.075, blue: 0.14, alpha: 1)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 3.4
        camera.position = SCNVector3(0, 1.0, 8); scene.rootNode.addChildNode(camera)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .omni; key.light?.intensity = 1100
        key.position = SCNVector3(-3, 5, 6); scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient
        fill.light?.color = UIColor(red: 0.55, green: 0.7, blue: 0.9, alpha: 1); fill.light?.intensity = 450
        scene.rootNode.addChildNode(fill)
        root.eulerAngles = SCNVector3(-0.10, -0.18, 0)
        scene.rootNode.addChildNode(root)
        func material(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = color; m.roughness.contents = 0.45; m.metalness.contents = 0.15; return m
        }
        let shell = material(UIColor(red: 0.25, green: 0.82, blue: 0.75, alpha: 1))
        let jointMaterial = material(UIColor(red: 0.08, green: 0.3, blue: 0.4, alpha: 1))
        let tipMaterial = material(UIColor(red: 0.98, green: 0.78, blue: 0.35, alpha: 1))
        let palm = SCNBox(width: 1.28, height: 1.15, length: 0.28, chamferRadius: 0.22)
        palm.materials = [shell]
        let palmNode = SCNNode(geometry: palm); palmNode.position = SCNVector3(0, 0.48, 0); root.addChildNode(palmNode)
        let wrist = SCNCapsule(capRadius: 0.30, height: 0.65); wrist.materials = [shell]
        let wristNode = SCNNode(geometry: wrist); wristNode.position = SCNVector3(0,-0.33,0); root.addChildNode(wristNode)
        for f in 0..<5 {
            var row: [SCNNode] = [], segments: [SCNNode] = []
            for j in 0..<4 {
                let sphere = SCNSphere(radius: j == 3 ? 0.105 : 0.09)
                sphere.materials = [j == 3 && f < 2 ? tipMaterial : jointMaterial]
                let node = SCNNode(geometry: sphere); root.addChildNode(node); row.append(node)
                if j < 3 {
                    let shape = SCNCapsule(capRadius: 0.105, height: 1)
                    shape.materials = [shell]
                    let bone = SCNNode(geometry: shape); root.addChildNode(bone); segments.append(bone)
                }
            }
            joints.append(row); bones.append(segments)
        }
        let ring = SCNTorus(ringRadius: 0.20, pipeRadius: 0.018)
        let glowMaterial = SCNMaterial(); glowMaterial.diffuse.contents = UIColor.systemYellow; glowMaterial.emission.contents = UIColor.systemYellow
        ring.materials = [glowMaterial]; glow.geometry = ring; glow.eulerAngles.x = .pi / 2
        root.addChildNode(glow)
        pose(pinch: 0, horizontal: 0)
    }
    func pose(pinch: Float, horizontal: Float) {
        let open: [[SIMD3<Float>]] = [
            [SIMD3(-0.60,0.35,0),SIMD3(-0.91,0.65,0),SIMD3(-1.11,0.91,0.02),SIMD3(-1.18,1.17,0.02)],
            [SIMD3(-0.46,0.96,0),SIMD3(-0.49,1.40,0),SIMD3(-0.52,1.76,0),SIMD3(-0.54,2.03,0)],
            [SIMD3(-0.06,1.01,0),SIMD3(-0.04,1.52,0),SIMD3(-0.01,1.93,0),SIMD3(0,2.24,0)],
            [SIMD3(0.32,0.99,0),SIMD3(0.39,1.44,0),SIMD3(0.44,1.79,0),SIMD3(0.48,2.06,0)],
            [SIMD3(0.59,0.83,0),SIMD3(0.76,1.16,0),SIMD3(0.85,1.43,0),SIMD3(0.91,1.66,0)]
        ]
        let closed: [[SIMD3<Float>]] = [
            [SIMD3(-0.60,0.35,0),SIMD3(-0.78,0.82,0.1),SIMD3(-0.60,1.14,0.3),SIMD3(-0.44,1.42,0.45)],
            [SIMD3(-0.46,0.96,0),SIMD3(-0.47,1.46,0.1),SIMD3(-0.45,1.65,0.3),SIMD3(-0.44,1.42,0.45)]
        ]
        for f in 0..<5 {
            let points = (0..<4).map { j in f < 2 ? open[f][j] + (closed[f][j] - open[f][j]) * pinch : open[f][j] }
            for j in 0..<4 { joints[f][j].simdPosition = points[j] }
            for j in 0..<3 {
                let delta = points[j+1] - points[j]
                bones[f][j].simdPosition = (points[j] + points[j+1]) / 2
                bones[f][j].simdOrientation = simd_quatf(from: SIMD3(0,1,0), to: simd_normalize(delta))
                bones[f][j].simdScale = SIMD3(1, simd_length(delta), 1)
            }
        }
        root.position.x = horizontal
        glow.position = SCNVector3(-0.44, 1.42, 0.57); glow.opacity = CGFloat(max(0, (pinch - 0.75) * 4))
    }
    func animate(_ lesson: GestureLesson, reduceMotion: Bool) {
        root.removeAllActions()
        if reduceMotion {
            pose(pinch: lesson == .stop ? 0 : 1, horizontal: lesson == .left ? -0.55 : lesson == .right ? 0.55 : 0)
            return
        }
        let action = SCNAction.customAction(duration: 4.5) { [weak self] _, elapsed in
            let t = Float(elapsed / 4.5)
            func smooth(_ value: Float) -> Float { let v = max(0,min(1,value)); return v*v*(3-2*v) }
            let pinch = lesson == .stop ? 1 - smooth((t - 0.18) / 0.32) : smooth((t - 0.08) / 0.25)
            let shift = smooth((t - 0.38) / 0.28) * (1 - smooth((t - 0.82) / 0.18))
            let horizontal: Float = lesson == .left ? -0.70 * shift : lesson == .right ? 0.70 * shift : 0
            self?.pose(pinch: pinch, horizontal: horizontal)
        }
        root.runAction(.repeatForever(action))
    }
}

struct HandAnimationView: UIViewRepresentable {
    let lesson: GestureLesson
    let reduceMotion: Bool
    final class Coordinator {
        let hand = DemoHand()
        var lesson: GestureLesson?
        var reduce = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.hand.scene
        view.isPlaying = true; view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling4X
        view.accessibilityLabel = "3D demonstration: \(lesson.title)"
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.lesson != lesson || context.coordinator.reduce != reduceMotion {
            context.coordinator.lesson = lesson; context.coordinator.reduce = reduceMotion
            context.coordinator.hand.animate(lesson, reduceMotion: reduceMotion)
            view.accessibilityLabel = "3D demonstration: \(lesson.title)"
        }
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.hand.root.removeAllActions(); view.isPlaying = false; view.scene = nil
    }
}

struct GestureGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lesson: GestureLesson = .forward
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Rover stopped while this guide is open", systemImage: "pause.circle.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HandAnimationView(lesson: lesson, reduceMotion: reduceMotion)
                        .frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(alignment: .topLeading) {
                            Label(lesson.title, systemImage: lesson.symbol).font(.headline).foregroundStyle(.white)
                                .padding(12).background(.black.opacity(0.3), in: Capsule()).padding(14)
                        }
                    HStack(spacing: 8) {
                        ForEach(GestureLesson.allCases) { item in
                            Button { lesson = item } label: {
                                Image(systemName: item.symbol).font(.title3).frame(maxWidth: .infinity).padding(.vertical, 12)
                            }.buttonStyle(.bordered).tint(lesson == item ? .blue : .gray)
                                .accessibilityLabel(item.title)
                        }
                    }
                    Text(lesson.title).font(.title2.bold())
                    Text(lesson.instruction).font(.body)
                    Divider()
                    Label("Phone upright on a stand, front camera facing you", systemImage: "iphone.gen3")
                    Label("Only thumb and index matter; keep their tips and index knuckle visible", systemImage: "hand.raised.fingers.spread")
                    Label("Preview is mirrored: screen-left steers left", systemImage: "arrow.left.arrow.right")
                    Text("Tap Enable driving again after closing this guide. Hand mode moves forward only, capped at 35% power; use Joystick for reversing.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("Hand gestures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
