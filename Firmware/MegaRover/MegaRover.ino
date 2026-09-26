#include <AFMotor.h>
#include "RoverProtocol.h"

// Keep false until serial wiring and motor power have been checked.
constexpr bool DRIVE_ENABLED = false; // Bench interlock pending power checks.
constexpr uint8_t LEFT_PORT = 4;  // Owner confirmed.
constexpr uint8_t RIGHT_PORT = 1; // Owner confirmed.
AF_DCMotor m1(1), m2(2), m3(3), m4(4);
AF_DCMotor *motors[] = {nullptr, &m1, &m2, &m3, &m4};
RoverProtocol rover;
char line[32];
uint8_t used = 0;
bool dropping = false;
uint32_t partialSince = 0;

void applyMotor(AF_DCMotor *motor, int value) {
    motor->setSpeed(abs(value)); // Preserve protocol's conservative 160/255 cap.
    motor->run(value == 0 ? RELEASE : value > 0 ? FORWARD : BACKWARD);
}
void applyOutputs() {
    for (uint8_t p = 1; p <= 4; ++p) {
        int value = 0;
        if (DRIVE_ENABLED && rover.armed)
            value = p == LEFT_PORT ? rover.left : p == RIGHT_PORT ? rover.right : 0;
        applyMotor(motors[p], value);
    }
}
void reply(const char *s) {
    Serial1.println(s);
    Serial.println(s); // USB diagnostic output only; USB cannot issue drive commands.
}
void setup() {
    rover.enabled = DRIVE_ENABLED;
    rover.stop(); applyOutputs();
    Serial.begin(115200);
    Serial1.begin(115200); // Mega RX1=19, TX1=18.
    reply("SAFE:BOOT");
}
void loop() {
    if (const char *s = rover.tick(millis())) { applyOutputs(); reply(s); }
    // Bound work per loop so a noisy serial line cannot starve the watchdog.
    for (uint8_t budget = 0; budget < 32 && Serial1.available(); ++budget) {
        char c = Serial1.read();
        if (c == '\n') {
            if (!dropping) {
                line[used] = 0;
                const char *s = rover.command(line, millis());
                applyOutputs(); reply(s);
            }
            used = 0; dropping = false;
        } else if (!dropping) {
            if (!used) partialSince = millis();
            if (c == '\r') continue;
            if (c < 32 || c > 126 || used >= sizeof(line) - 1) {
                rover.stop(); applyOutputs(); reply("ERR:FRAME");
                dropping = true; used = 0;
            } else line[used++] = c;
        }
    }
    if (used && uint32_t(millis() - partialSince) > 150) {
        rover.stop(); applyOutputs(); reply("ERR:FRAME");
        used = 0; dropping = true; // Discard remainder until newline.
    }
}
