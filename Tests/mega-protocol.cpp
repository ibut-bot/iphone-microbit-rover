#include "../Firmware/MegaRover/RoverProtocol.h"
#include <assert.h>
#include <stdio.h>
void expect(const char *actual, const char *wanted) { assert(actual && !strcmp(actual, wanted)); }
int main() {
    RoverProtocol r;
    expect(r.command("HELLO", 0), "ROVER:1");
    expect(r.command("ARM", 0), "ERR:CONFIG");
    r.enabled = true;
    expect(r.command("D:50:50", 1), "ERR:DISARMED");
    expect(r.command("ARM", 10), "OK:ARM");
    expect(r.command("D:-160:160", 20), "OK:D");
    assert(r.left == -160 && r.right == 160);
    assert(!r.tick(420));
    expect(r.tick(421), "SAFE:TIMEOUT");
    assert(!r.armed && r.left == 0 && r.right == 0);
    const char *invalid[] = {"D:161:0", "D:1x:0", "D::0", "D:1:2:3", "D:+1:0", "ARMjunk"};
    for (auto s : invalid) {
        r.command("ARM", 500); r.command("D:60:60", 501);
        assert(!strncmp(r.command(s, 502), "ERR:", 4));
        assert(!r.armed && !r.left && !r.right);
    }
    r.command("ARM", 1000);
    expect(r.command("D:20:20", 1401), "ERR:DISARMED");
    r.command("ARM", 2000); r.command("PING", 2300);
    expect(r.tick(2401), "SAFE:TIMEOUT");
    r.command("ARM", UINT32_MAX - 100);
    assert(!r.tick(299));
    expect(r.tick(300), "SAFE:TIMEOUT");
    r.command("ARM", 400); r.command("D:40:30", 401);
    expect(r.command("HELLO", 402), "ROVER:1"); assert(!r.armed && !r.left);
    r.command("ARM", 500); expect(r.command("STOP", 501), "OK:STOP"); assert(!r.armed);
    puts("Mega protocol: bench lock, parsing, stop, stale drive, watchdog and clock rollover passed");
}
