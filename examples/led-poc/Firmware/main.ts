// Phone <-> micro:bit proof of concept. No motors or expansion board required.
let connected = false
bluetooth.startUartService()
bluetooth.onBluetoothConnected(function () {
    connected = true
    basic.showIcon(IconNames.Yes)
})
bluetooth.onBluetoothDisconnected(function () {
    connected = false
    basic.showIcon(IconNames.SmallDiamond)
})
bluetooth.onUartDataReceived(serial.delimiters(Delimiters.NewLine), function () {
    let command = bluetooth.uartReadUntil(serial.delimiters(Delimiters.NewLine))
    if (command == "PING") {
        bluetooth.uartWriteString("PONG\n")
    } else if (command == "HEART") {
        basic.showIcon(IconNames.Heart)
        bluetooth.uartWriteString("OK:HEART\n")
    } else if (command == "SMILE") {
        basic.showIcon(IconNames.Happy)
        bluetooth.uartWriteString("OK:SMILE\n")
    } else if (command == "CLEAR") {
        basic.clearScreen()
        bluetooth.uartWriteString("OK:CLEAR\n")
    } else {
        bluetooth.uartWriteString("ERR:COMMAND\n")
    }
})
input.onButtonPressed(Button.A, function () {
    if (connected) bluetooth.uartWriteString("BUTTON:A\n")
})
input.onButtonPressed(Button.B, function () {
    if (connected) bluetooth.uartWriteString("BUTTON:B\n")
})
basic.showIcon(IconNames.SmallDiamond)
