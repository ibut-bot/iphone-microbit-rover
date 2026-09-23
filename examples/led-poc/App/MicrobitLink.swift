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
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        resetConnection()
        status = "Disconnected"
    }
    private func resetConnection() {
        ready = false; connected = false; peripheral = nil
        writeCharacteristic = nil; receiveCharacteristic = nil
        receiveBuffer.removeAll(); waitingFor = nil
        connectTimer?.invalidate(); replyTimer?.invalidate()
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Finding test service…"
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
        ready = true; status = "Connected — ready to test"; record("UART connected; replies enabled")
    }
    func send(_ command: String) {
        guard ready, let peripheral, let writeCharacteristic else { return }
        guard waitingFor == nil else { record("Wait for the previous reply"); return }
        let expected = command == "PING" ? "PONG" : "OK:\(command)"
        waitingFor = expected
        peripheral.writeValue(Data((command + "\n").utf8), for: writeCharacteristic, type: .withResponse)
        record("→ \(command)")
        replyTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self, self.waitingFor != nil else { return }
            self.waitingFor = nil
            self.status = "No reply. Check the supplied firmware is running."
            self.record("Reply timed out")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { waitingFor = nil; replyTimer?.invalidate(); status = "Send failed"; record(error.localizedDescription) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == receiveCharacteristic?.uuid, let data = characteristic.value else { return }
        receiveBuffer.append(data)
        while let newline = receiveBuffer.firstIndex(of: 10) {
            let line = String(decoding: receiveBuffer[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            lastReply = line; record("← \(line)")
            if line == waitingFor {
                waitingFor = nil; replyTimer?.invalidate()
                status = "Success — command and reply confirmed"
            }
        }
        if receiveBuffer.count > 1024 { receiveBuffer.removeAll(); record("Discarded oversized reply") }
    }
}

struct ContentView: View {
    @StateObject private var link = BluetoothLink()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(link.status, systemImage: link.ready ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(link.ready ? .green : .primary)
                    if link.connected {
                        Button("Disconnect", role: .destructive) { link.disconnect() }
                    } else {
                        Button(link.scanning ? "Stop scanning" : "Find micro:bit") {
                            if link.scanning { link.stopScan() } else { link.scan() }
                        }.disabled(!link.bluetoothAvailable)
                    }
                    ForEach(link.devices) { device in
                        Button { link.connect(device) } label: {
                            HStack { Text(device.name); Spacer(); Text("\(device.rssi) dBm").foregroundStyle(.secondary) }
                        }.disabled(link.connected)
                    }
                } header: { Text("1 · Connect") } footer: {
                    Text("Power your micro:bit and install the supplied firmware. Keep this app open during the test.")
                }
                Section("2 · Send a command") {
                    Button { link.send("PING") } label: { Label("Test round trip", systemImage: "arrow.left.arrow.right") }
                    Button { link.send("HEART") } label: { Label("Show heart", systemImage: "heart.fill") }
                    Button { link.send("SMILE") } label: { Label("Show smile", systemImage: "face.smiling") }
                    Button { link.send("CLEAR") } label: { Label("Clear LEDs", systemImage: "square.dashed") }
                }.disabled(!link.ready)
                Section {
                    Text(link.lastReply).font(.title3.monospaced()).textSelection(.enabled)
                    Text("Press button A or B on the micro:bit. Its message should appear here.").foregroundStyle(.secondary)
                } header: { Text("3 · Test the return path") }
                Section("Activity") {
                    if link.log.isEmpty { Text("Connection and test results will appear here.").foregroundStyle(.secondary) }
                    ForEach(Array(link.log.enumerated()), id: \.offset) { _, item in
                        Text(item).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Microbit Link")
        }
    }
}
