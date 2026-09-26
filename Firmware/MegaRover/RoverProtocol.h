#pragma once
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Hardware-independent command gate. Only valid drive commands refresh the timer.
struct RoverProtocol {
    bool armed = false;
    bool enabled = false; // Explicit hardware commissioning gate.
    uint32_t lastDrive = 0;
    int left = 0, right = 0;
    void stop() { armed = false; left = right = 0; }
    static bool number(const char *s, int &out) {
        size_t n = strlen(s);
        if (!n || n > 4) return false;
        size_t i = s[0] == '-' ? 1 : 0;
        if (i == n) return false;
        for (; i < n; ++i) if (s[i] < '0' || s[i] > '9') return false;
        out = atoi(s);
        return out >= -160 && out <= 160;
    }
    const char *tick(uint32_t now) {
        if (armed && uint32_t(now - lastDrive) > 400) {
            stop(); return "SAFE:TIMEOUT";
        }
        return nullptr;
    }
    const char *command(const char *s, uint32_t now) {
        // An expired arm cannot be revived by a late drive packet.
        tick(now);
        if (!strcmp(s, "HELLO")) { stop(); return "ROVER:1"; }
        if (!strcmp(s, "STOP")) { stop(); return "OK:STOP"; }
        if (!strcmp(s, "PING")) return "PONG";
        if (!strcmp(s, "ARM")) {
            stop();
            if (!enabled) return "ERR:CONFIG";
            armed = true; lastDrive = now; return "OK:ARM";
        }
        if (!strncmp(s, "D:", 2)) {
            char copy[32];
            if (strlen(s) >= sizeof(copy)) { stop(); return "ERR:DRIVE"; }
            strcpy(copy, s + 2);
            char *colon = strchr(copy, ':');
            if (!colon || strchr(colon + 1, ':')) { stop(); return "ERR:DRIVE"; }
            *colon++ = 0;
            int l, r;
            if (!number(copy, l) || !number(colon, r)) { stop(); return "ERR:RANGE"; }
            if (!armed) { stop(); return "ERR:DISARMED"; }
            left = l; right = r; lastDrive = now; return "OK:D";
        }
        stop(); return "ERR:COMMAND";
    }
};
