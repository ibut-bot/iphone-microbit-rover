#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <atomic>

// Same Nordic UART service as the micro:bit; existing iPhone app discovers it.
constexpr char SERVICE[] = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr char RX_UUID[] = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr char TX_UUID[] = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr int UART_RX = 16, UART_TX = 17;
struct Packet { uint32_t epoch, time; uint8_t count; char data[64]; };
QueueHandle_t packets;
std::atomic<uint32_t> epoch{0};
std::atomic<bool> connected{false}, overflow{false};
BLECharacteristic *notifications;
uint32_t activeEpoch = 0, sentAt = 0, partialAt = 0;
bool ready = false;
char expected[20] = {}, command[32] = {}, response[32] = {};
size_t commandSize = 0, responseSize = 0;

void notify(const char *s) {
    Serial.println(s);
    if (connected.load()) {
        String message = String(s) + "\n";
        notifications->setValue(message.c_str()); notifications->notify();
    }
}
void stopLink(const char *reason, bool discardPackets = true) {
    // Actual motor stop is always handled by Mega; its watchdog also covers cable loss.
    Serial2.print("STOP\n");
    ready = false; expected[0] = 0;
    commandSize = responseSize = 0;
    if (discardPackets) xQueueReset(packets);
    if (reason) notify(reason);
}
class ConnectionCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer *) override { connected.store(true); epoch.fetch_add(1); }
    void onDisconnect(BLEServer *) override { connected.store(false); epoch.fetch_add(1); }
};
class WriteCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *c) override {
        auto value = c->getValue();
        if (value.empty()) return;
        if (value.size() > sizeof(Packet::data)) { overflow.store(true); return; }
        Packet p{}; p.epoch = epoch.load(); p.time = millis(); p.count = value.size();
        memcpy(p.data, value.data(), p.count);
        if (xQueueSend(packets, &p, 0) != pdTRUE) overflow.store(true);
    }
};
void forwardCommand() {
    command[commandSize] = 0;
    if (!strcmp(command, "STOP")) {
        stopLink(nullptr); strcpy(expected, "OK:STOP"); sentAt = millis(); return;
    }
    if (expected[0]) { stopLink("ERR:BUSY"); return; }
    if (strcmp(command, "HELLO") && !ready) { stopLink("ERR:LINK"); return; }
    const char *ack = nullptr;
    if (!strcmp(command, "HELLO")) { ready = false; ack = "ROVER:1"; }
    else if (!strcmp(command, "ARM")) ack = "OK:ARM";
    else if (!strcmp(command, "PING")) ack = "PONG";
    else if (!strncmp(command, "D:", 2)) ack = "OK:D";
    else { stopLink("ERR:COMMAND"); return; }
    strcpy(expected, ack); sentAt = millis();
    Serial2.print(command); Serial2.print('\n');
}
void setup() {
    Serial.begin(115200);
    Serial2.begin(115200, SERIAL_8N1, UART_RX, UART_TX);
    packets = xQueueCreate(4, sizeof(Packet));
    if (!packets) { Serial.println("Queue allocation failed"); while (true) delay(1000); }
    BLEDevice::init("ESP32 Rover");
    auto server = BLEDevice::createServer();
    server->setCallbacks(new ConnectionCallbacks());
    auto service = server->createService(SERVICE);
    notifications = service->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
    notifications->addDescriptor(new BLE2902());
    auto input = service->createCharacteristic(RX_UUID, BLECharacteristic::PROPERTY_WRITE);
    input->setCallbacks(new WriteCallbacks());
    service->start();
    auto advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE); advertising->setScanResponse(true);
    advertising->start();
    stopLink(nullptr);
    Serial.println("ESP32 Rover bridge ready; UART RX=16 TX=17, 115200 baud");
}
void loop() {
    if (activeEpoch != epoch.load()) {
        activeEpoch = epoch.load(); stopLink(nullptr, false);
        while (Serial2.available()) Serial2.read();
        if (!connected.load()) BLEDevice::startAdvertising();
    }
    if (overflow.exchange(false)) stopLink("ERR:OVERFLOW");
    if (expected[0] && uint32_t(millis() - sentAt) > 250) stopLink("ERR:MEGA_TIMEOUT");
    if (commandSize && uint32_t(millis() - partialAt) > 150) stopLink("ERR:FRAME");
    Packet p;
    if (xQueueReceive(packets, &p, 0) == pdTRUE && connected.load() && p.epoch == activeEpoch) {
        if (uint32_t(millis() - p.time) > 150) stopLink("ERR:STALE");
        else for (uint8_t i = 0; i < p.count; ++i) {
            if (!connected.load() || epoch.load() != activeEpoch) break;
            char c = p.data[i];
            if (c == '\n') { forwardCommand(); commandSize = 0; }
            else if (c < 32 || c > 126 || commandSize >= sizeof(command) - 1) {
                stopLink("ERR:FRAME"); break;
            } else {
                if (!commandSize) partialAt = p.time;
                command[commandSize++] = c;
            }
        }
    }
    for (uint8_t budget = 0; budget < 64 && Serial2.available(); ++budget) {
        char c = Serial2.read();
        if (c == '\r') continue;
        if (c == '\n') {
            response[responseSize] = 0;
            if (!strncmp(response, "ERR:", 4) || !strncmp(response, "SAFE:", 5)) {
                char saved[32]; strcpy(saved, response); stopLink(saved);
            } else if (expected[0] && !strcmp(response, expected)) {
                if (!strcmp(response, "ROVER:1")) ready = true;
                if (!strcmp(response, "OK:STOP")) ready = true;
                expected[0] = 0; notify(response);
            }
            responseSize = 0;
        } else if (c < 32 || c > 126 || responseSize >= sizeof(response) - 1) {
            stopLink("ERR:SERIAL");
        } else response[responseSize++] = c;
    }
    delay(2);
}
