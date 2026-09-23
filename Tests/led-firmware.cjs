const vm = require('node:vm');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const handlers = {}, sent = [], shown = [];
let incoming = '';
const context = {
 bluetooth: {
  startUartService() {},
  onBluetoothConnected(fn) {handlers.connect=fn},
  onBluetoothDisconnected(fn) {handlers.disconnect=fn},
  onUartDataReceived(_,fn) {handlers.receive=fn},
  uartReadUntil() {return incoming},
  uartWriteString(value) {sent.push(value)}
 },
 basic: {showIcon(icon) {shown.push(icon)},clearScreen() {shown.push('clear')}},
 input: {onButtonPressed(button,fn) {handlers[button]=fn}},
 serial: {delimiters() {return '\n'}},
 Delimiters: {NewLine: 10}, Button: {A:'A', B:'B'},
 IconNames: {Yes:'yes',SmallDiamond:'diamond',Heart:'heart',Happy:'smile'}
};
vm.runInNewContext(fs.readFileSync('examples/led-poc/Firmware/main.ts','utf8'),context);
handlers.A(); assert.equal(sent.length,0);
handlers.connect(); assert.equal(shown.at(-1),'yes');
for(const [command,reply,icon] of [['PING','PONG',null],['HEART','OK:HEART','heart'],['SMILE','OK:SMILE','smile'],['CLEAR','OK:CLEAR','clear'],['UNKNOWN','ERR:COMMAND',null]]) {
 incoming=command; handlers.receive(); assert.equal(sent.at(-1),reply+'\n');
 if(icon) assert.equal(shown.at(-1),icon);
 assert.ok(Buffer.byteLength(sent.at(-1))<=20);
}
handlers.A(); assert.equal(sent.at(-1),'BUTTON:A\n');
handlers.B(); assert.equal(sent.at(-1),'BUTTON:B\n');
handlers.disconnect(); const count=sent.length; handlers.B(); assert.equal(sent.length,count);
assert.equal(shown.at(-1),'diamond');
console.log('PASS: command replies, LED actions, button events, disconnected buttons, message size');
