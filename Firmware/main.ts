// Rover M1/M3. No movement until ARM; fresh DRIVE required every 400 ms.
let linked = false
let armed = false
let lastDrive = 0
function halt() {
    SuperBitV2.MotorRun(SuperBitV2.enMotors.M1, 0)
    SuperBitV2.MotorRun(SuperBitV2.enMotors.M3, 0)
}
function disarm() {
    armed = false
    halt()
}
function reply(message: string) {
    if (linked) bluetooth.uartWriteString(message + "\n")
}
// Strict integer parser: reject malformed data instead of partial parseInt results.
function motorValue(value: string): number {
    if (value.length == 0 || value.length > 4) return 9999
    let start = value.charAt(0) == "-" ? 1 : 0
    if (start == value.length) return 9999
    for (let i = start; i < value.length; i++) {
        if (value.charAt(i) < "0" || value.charAt(i) > "9") return 9999
    }
    let parsed = parseInt(value)
    if (parsed < -160 || parsed > 160) return 9999
    return parsed
}
disarm()
bluetooth.startUartService()
bluetooth.onBluetoothConnected(function () {
    disarm()
    linked = true
    basic.showIcon(IconNames.Yes)
})
bluetooth.onBluetoothDisconnected(function () {
    linked = false
    disarm()
    basic.showIcon(IconNames.SmallDiamond)
})
bluetooth.onUartDataReceived(serial.delimiters(Delimiters.NewLine), function () {
    let command = bluetooth.uartReadUntil(serial.delimiters(Delimiters.NewLine))
    if (command == "HELLO") {
        disarm()
        reply("ROVER:1")
    } else if (command == "STOP") {
        disarm()
        reply("OK:STOP")
    } else if (command == "ARM" && linked) {
        halt()
        lastDrive = input.runningTime()
        armed = true
        reply("OK:ARM")
    } else if (command.substr(0, 2) == "D:") {
        let parts = command.split(":")
        if (parts.length != 3) {
            disarm()
            reply("ERR:DRIVE")
        } else {
            let m1 = motorValue(parts[1])
            let m3 = motorValue(parts[2])
            if (m1 == 9999 || m3 == 9999) {
                disarm()
                reply("ERR:RANGE")
            } else if (!armed || !linked) {
                halt()
                reply("ERR:DISARMED")
            } else {
                lastDrive = input.runningTime()
                SuperBitV2.MotorRun(SuperBitV2.enMotors.M1, m1)
                SuperBitV2.MotorRun(SuperBitV2.enMotors.M3, m3)
                reply("OK:D")
            }
        }
    } else if (command == "PING") {
        reply("PONG")
    } else {
        disarm()
        reply("ERR:COMMAND")
    }
})
basic.forever(function () {
    if (armed && input.runningTime() - lastDrive > 400) {
        disarm()
        reply("SAFE:TIMEOUT")
    }
    basic.pause(20)
})
input.onButtonPressed(Button.A, function () { disarm(); reply("SAFE:BUTTON") })
input.onButtonPressed(Button.B, function () { disarm(); reply("SAFE:BUTTON") })
basic.showIcon(IconNames.SmallDiamond)
