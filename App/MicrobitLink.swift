import SwiftUI
import CoreBluetooth

@main
struct MicrobitLinkApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct NearbyBit: Identifiable {
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    var id: UUID { peripheral.identifier }
}

final class BluetoothLink: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "Starting Bluetooth…"
    @Published var devices: [NearbyBit] = []
    @Published var log: [String] = []
    @Published var ready = false
    @Published var armed = false
    @Published var roverCompatible = false
    @Published var joystick = CGSize.zero
    @Published var motor1 = 0
    @Published var motor3 = 0
    @Published var handDecision = HandDecision(message: "Open your hand to begin")
    private var handMode = false
    private var handGate = HandDriveGate()
    private var lastHandFrameAt: TimeInterval = 0
    func setHandMode(_ enabled: Bool) {
        emergencyStop()
        handMode = enabled
        handGate.reset()
        lastHandFrameAt = 0
    }
    func receiveHandSample(_ sample: HandSample?) {
        guard handMode else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastHandFrameAt = sample?.capturedAt ?? now
        handDecision = handGate.evaluate(sample, now: now, enabled: armed)
        if handDecision.moving {
            move(CGSize(width: handDecision.steering, height: -handDecision.forward))
        } else if joystick != .zero { releaseJoystick() }
    }
    var speedLimit = 0.35
    var swapWheels = false
    var reverseM1 = false
    var reverseM3 = false
    private var driveTimer: Timer?
    private var lastSentAt = Date.distantPast
    private var pendingCommand: String?
    private var cancelArming = false
    @Published var scanning = false
    @Published var connected = false
    @Published var bluetoothAvailable = false
    @Published var lastReply = "No reply yet"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var receiveCharacteristic: CBCharacteristic?
    private var receiveBuffer = Data()
    private var scanTimer: Timer?
    private var connectTimer: Timer?
    private var replyTimer: Timer?
    private var waitingFor: String?
    private let uart = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    private func record(_ text: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(text)", at: 0)
        if log.count > 80 { log.removeLast(log.count - 80) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothAvailable = central.state == .poweredOn
        if !bluetoothAvailable { resetConnection(); stopScan() }
        switch central.state {
        case .poweredOn: status = "Ready to find your micro:bit"
        case .poweredOff: status = "Turn Bluetooth on in iPhone Settings"
        case .unauthorized: status = "Allow Bluetooth for Microbit Link in Settings"
        case .unsupported: status = "Bluetooth is unavailable on this device"
        default: status = "Bluetooth is starting…"
        }
    }
    func scan() {
        guard bluetoothAvailable, peripheral == nil else { return }
        devices = []
        scanning = true
        status = "Looking for micro:bits…"
        // micro:bit firmware may advertise its name without the UART UUID.
        central.scanForPeripherals(withServices: nil)
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.stopScan()
            self.status = self.devices.isEmpty ? "No micro:bit found. Check power and firmware." : "Tap your micro:bit to connect"
        }
    }
    func stopScan() { central.stopScan(); scanning = false; scanTimer?.invalidate() }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.lowercased().contains("micro:bit") || name.lowercased().contains("microbit") || services.contains(uart) else { return }
        let device = NearbyBit(peripheral: peripheral, name: name.isEmpty ? "micro:bit UART" : name, rssi: RSSI.intValue)
        if let i = devices.firstIndex(where: { $0.id == device.id }) { devices[i] = device } else { devices.append(device) }
    }
    func connect(_ device: NearbyBit) {
        stopScan()
        peripheral = device.peripheral
        peripheral?.delegate = self
        connected = true
        status = "Connecting to \(device.name)…"
        central.connect(device.peripheral)
        connectTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self, !self.ready else { return }
            self.disconnect()
            self.status = "Connection timed out. Check pairing and try again."
        }
    }
    func disconnect() {
        emergencyStop()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        resetConnection()
        status = "Disconnected"
    }
    private func resetConnection() {
        driveTimer?.invalidate()
        armed = false; roverCompatible = false; joystick = .zero
        motor1 = 0; motor3 = 0; pendingCommand = nil
        ready = false; connected = false; peripheral = nil
        writeCharacteristic = nil; receiveCharacteristic = nil
        receiveBuffer.removeAll(); waitingFor = nil
        connectTimer?.invalidate(); replyTimer?.invalidate()
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Finding rover service…"
        peripheral.discoverServices([uart])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        resetConnection(); status = "Could not connect: \(error?.localizedDescription ?? "Try again")"
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        resetConnection(); status = "Disconnected. Scan to reconnect."; record("Disconnected")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == uart }) else {
            status = "UART service missing. Install the supplied micro:bit firmware."; return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { status = error!.localizedDescription; return }
        // Discover by properties: micro:bit UART directions differ from some Nordic examples.
        for characteristic in service.characteristics ?? [] {
            if characteristic.properties.contains(.write) { writeCharacteristic = characteristic }
            if characteristic.properties.contains(.indicate) || characteristic.properties.contains(.notify) {
                receiveCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        if writeCharacteristic == nil || receiveCharacteristic == nil { status = "Firmware has incompatible UART characteristics" }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == receiveCharacteristic?.uuid else { return }
        guard error == nil, characteristic.isNotifying, writeCharacteristic != nil else {
            status = "Could not enable replies. Check Bluetooth pairing."; return
        }
        connectTimer?.invalidate()
        ready = true; status = "Checking rover firmware…"; record("UART connected")
        send("HELLO")
        driveTimer?.invalidate()
        driveTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(driveTimer!, forMode: .common)
    }
    // One outstanding application reply: never accumulate a queue of old drive commands.
    private func transmit(_ command: String) {
        guard ready, let peripheral, let writeCharacteristic else { return }
        waitingFor = command == "HELLO" ? "ROVER:1" : command == "PING" ? "PONG" : command.hasPrefix("D:") ? "OK:D" : "OK:\(command)"
        lastSentAt = Date()
        peripheral.writeValue(Data((command + "\n").utf8), for: writeCharacteristic, type: .withResponse)
        if !command.hasPrefix("D:") { record("→ \(command)") }
    }
    func send(_ command: String) {
        guard ready else { return }
        if waitingFor == nil { transmit(command) }
    }
    func enableDriving() {
        guard ready, roverCompatible, waitingFor == nil else { return }
        handGate.reset()
        cancelArming = false
        joystick = .zero
        send("ARM")
    }
    func emergencyStop() {
        handGate.reset()
        handDecision = HandDecision(message: "Stopped · enable driving to begin")
        cancelArming = true
        armed = false; joystick = .zero; motor1 = 0; motor3 = 0
        // STOP takes precedence over any pending joystick value.
        pendingCommand = "STOP"
        if waitingFor == nil, ready { pendingCommand = nil; transmit("STOP") }
    }
    func move(_ value: CGSize) {
        guard armed else { return }
        joystick = value
        updateMotors()
    }
    func releaseJoystick() {
        joystick = .zero; motor1 = 0; motor3 = 0
        if armed {
            if waitingFor == nil { transmit("D:0:0") }
            else if pendingCommand != "STOP" { pendingCommand = "D:0:0" }
        }
    }
    private func updateMotors() {
        let mixed = RoverMix.motors(x: joystick.width, y: -joystick.height, limit: handMode ? min(speedLimit, 0.35) : speedLimit,
                                    swap: swapWheels, reverse1: reverseM1, reverse3: reverseM3)
        motor1 = mixed.0; motor3 = mixed.1
    }
    private func tick() {
        guard ready else { return }
        if armed && handMode && ProcessInfo.processInfo.systemUptime - lastHandFrameAt > HandDriveGate.maxFrameAge {
            emergencyStop()
            status = "Camera stalled — stopped. Enable driving to resume."
        }
        if waitingFor != nil {
            if Date().timeIntervalSince(lastSentAt) > 0.35 {
                armed = false; cancelArming = true; joystick = .zero; motor1 = 0; motor3 = 0
                pendingCommand = nil; waitingFor = nil
                // Firmware independently disarms after 400 ms without a valid drive packet.
                status = "Reply timed out — stopped. Reconnect to drive."
                record(status)
                if let peripheral, let writeCharacteristic {
                    peripheral.writeValue(Data("STOP\n".utf8), for: writeCharacteristic, type: .withResponse)
                    central.cancelPeripheralConnection(peripheral)
                }
                ready = false; driveTimer?.invalidate()
            }
            return
        }
        if let command = pendingCommand { pendingCommand = nil; transmit(command); return }
        if armed {
            updateMotors()
            transmit("D:\(motor1):\(motor3)")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            record(error.localizedDescription)
            disconnect()
            status = "Bluetooth write failed — stopped"
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == receiveCharacteristic?.uuid, let data = characteristic.value else { return }
        receiveBuffer.append(data)
        while let newline = receiveBuffer.firstIndex(of: 10) {
            let line = String(decoding: receiveBuffer[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            lastReply = line
            if line != "OK:D" { record("← \(line)") }
            if line.hasPrefix("SAFE:") || line.hasPrefix("ERR:") {
                armed = false; cancelArming = true; joystick = .zero; motor1 = 0; motor3 = 0
                pendingCommand = nil; waitingFor = nil
                status = "Stopped: \(line)"
            }
            if line == waitingFor {
                waitingFor = nil; replyTimer?.invalidate()
                if line == "ROVER:1" { roverCompatible = true; status = "Connected — tap Enable driving" }
                if line == "OK:ARM", !cancelArming { armed = true; status = handMode ? "Driving enabled — open your hand, then pinch" : "Driving enabled — hold the joystick" }
                if line == "OK:STOP" { armed = false; status = "Stopped — tap Enable driving to resume" }
                if let command = pendingCommand { pendingCommand = nil; transmit(command) }
            }
        }
        if receiveBuffer.count > 1024 { receiveBuffer.removeAll(); record("Discarded oversized reply") }
    }
}

// x: right, y: forward. Output order is physical board ports M1, M3.
enum RoverMix {
    static func motors(x: Double, y: Double, limit: Double, swap: Bool, reverse1: Bool, reverse3: Bool) -> (Int, Int) {
        let deadzone = 0.10
        let magnitude = hypot(x, y)
        guard magnitude > deadzone else { return (0, 0) }
        let scale = (min(1, magnitude) - deadzone) / (1 - deadzone) / magnitude
        let forward = y * scale, turn = x * scale
        let left = forward + turn, right = forward - turn
        let norm = max(1, abs(left), abs(right))
        let ceiling = min(160, max(0, limit * 255))
        let l = Int((left / norm * ceiling).rounded())
        let r = Int((right / norm * ceiling).rounded())
        return ((swap ? r : l) * (reverse1 ? -1 : 1), (swap ? l : r) * (reverse3 ? -1 : 1))
    }
}

struct ContentView: View {
    @StateObject private var link = BluetoothLink()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("rover.speed") private var speed = 0.35
    @AppStorage("rover.swap") private var swap = false
    @AppStorage("rover.reverse1") private var reverse1 = false
    @AppStorage("rover.reverse3") private var reverse3 = false
    @GestureState private var touching = false
    @State private var settings = false
    @State private var guide = false
    @State private var handMode = false
    @StateObject private var camera = HandCamera()
    private func updateCamera() {
        if handMode && !guide && !settings && scenePhase == .active { camera.start() }
        else { camera.stop() }
    }

    private func configure() {
        link.speedLimit = speed; link.swapWheels = swap
        link.reverseM1 = reverse1; link.reverseM3 = reverse3
    }
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 14) {
                Label(link.status, systemImage: link.armed ? "steeringwheel" : "antenna.radiowaves.left.and.right")
                    .font(.subheadline).multilineTextAlignment(.center).frame(minHeight: 42)
                if !link.connected {
                    Button(link.scanning ? "Stop scanning" : "Find micro:bit") {
                        if link.scanning { link.stopScan() } else { link.scan() }
                    }.buttonStyle(.borderedProminent).disabled(!link.bluetoothAvailable)
                    ForEach(link.devices) { device in
                        Button(device.name) { link.connect(device) }.buttonStyle(.bordered)
                    }
                } else {
                    HStack {
                        Button("Disconnect") { link.disconnect() }
                        Spacer()
                        Button("Wheel setup", systemImage: "gearshape") { link.emergencyStop(); camera.stop(); settings = true }
                    }.font(.subheadline)
                }
                Picker("Control mode", selection: $handMode) {
                    Text("Joystick").tag(false)
                    Text("Hand control").tag(true)
                }.pickerStyle(.segmented)
                if handMode {
                    HandCameraView(camera: camera, decision: link.handDecision)
                    Text("Pinch to go · move hand left/right to steer · open to stop")
                        .font(.subheadline).multilineTextAlignment(.center)
                    Text("Forward only · maximum 35% power · front camera")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                HStack {
                    Text("Speed limit")
                    Slider(value: $speed, in: 0.20...0.60, step: 0.05).disabled(link.armed)
                    Text("\(Int((speed * 100).rounded()))%") .monospacedDigit()
                }.font(.subheadline)
                Text("FORWARD · toward the LED face").font(.caption).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let radius = max(1, (size - 72) / 2)
                    ZStack {
                        Circle().fill(Color.blue.opacity(link.armed ? 0.12 : 0.04))
                        Circle().stroke(Color.blue.opacity(0.25), lineWidth: 2)
                        Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1)
                        Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                        Image(systemName: "arrow.up").offset(y: -radius + 8).foregroundStyle(.secondary)
                        Image(systemName: "arrow.down").offset(y: radius - 8).foregroundStyle(.secondary)
                        Image(systemName: "arrow.left").offset(x: -radius + 8).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").offset(x: radius - 8).foregroundStyle(.secondary)
                        Circle().fill(link.armed ? Color.blue : Color.gray).frame(width: 70, height: 70)
                            .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                            .offset(x: link.joystick.width * radius, y: link.joystick.height * radius)
                    }
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .updating($touching) { _, state, _ in state = true }
                        .onChanged { value in
                            let dx = (value.location.x - size / 2) / radius
                            let dy = (value.location.y - size / 2) / radius
                            let length = max(1, hypot(dx, dy))
                            link.move(CGSize(width: dx / length, height: dy / length))
                        }
                        .onEnded { _ in link.releaseJoystick() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: 260)
                Text(link.armed ? "Hold to drive · release to stop" : "Enable driving to use the joystick")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("M1 \(link.motor1)   ·   M3 \(link.motor3)").font(.caption.monospaced())
                Text(link.lastReply).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding() }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Enable driving") { configure(); link.enableDriving() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!link.ready || !link.roverCompatible || link.armed || (handMode && !camera.running))
                    Button { link.emergencyStop() } label: {
                        Label("STOP", systemImage: "stop.fill").bold().frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.red).disabled(!link.ready)
                }.controlSize(.large)
                .padding().background(.bar)
            }
            .navigationTitle("Microbit Rover")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { link.emergencyStop(); camera.stop(); guide = true } label: {
                        Image(systemName: "hand.raised.fingers.spread.fill")
                    }.accessibilityLabel("Gesture guide")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
                configure()
                camera.onSample = { [weak link] sample in link?.receiveHandSample(sample) }
                #if targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--gesture-guide") { guide = true }
                if ProcessInfo.processInfo.arguments.contains("--hand-mode") { handMode = true }
                #endif
                updateCamera()
            }
            .onChange(of: handMode) { _, enabled in link.setHandMode(enabled); updateCamera() }
            .sheet(isPresented: $guide, onDismiss: { updateCamera() }) { GestureGuide() }
            .onChange(of: touching) { _, active in if !active && !handMode { link.releaseJoystick() } }
            .onChange(of: scenePhase) { _, phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active
                if phase != .active { link.emergencyStop() }
                updateCamera()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                link.emergencyStop(); camera.stop()
            }
            .sheet(isPresented: $settings, onDismiss: { updateCamera() }) {
                NavigationStack {
                    Form {
                        Section("Wheel mapping") {
                            Toggle("M1 is the right wheel", isOn: $swap)
                            Toggle("Reverse M1 direction", isOn: $reverse1)
                            Toggle("Reverse M3 direction", isOn: $reverse3)
                        }
                        Section {
                            Text("Left and right are viewed from behind, looking toward the micro:bit LED face. Start with the wheels lifted. If pushing forward spins a wheel backward, reverse that motor here.")
                            Text("Use the Super:bit board’s battery/power switch for the motors. The micro:bit USB cable alone may power only the controller.")
                            Text("Release stops movement. STOP, either micro:bit button, a lost connection, or 400 ms without drive commands disables driving.")
                        }
                        Section("Bluetooth activity") {
                            ForEach(Array(link.log.prefix(15).enumerated()), id: \.offset) { _, item in Text(item).font(.caption.monospaced()) }
                        }
                    }
                    .navigationTitle("Wheel setup")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { configure(); settings = false } } }
                }
            }
        }
    }
}
