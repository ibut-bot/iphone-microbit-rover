const vm=require('node:vm'), fs=require('node:fs'), assert=require('node:assert/strict');
const handlers={}, sent=[], motors={}; let incoming='', now=0;
const ctx={SuperBitV2:{enMotors:{M1:1,M3:3},MotorRun(p,v){motors[p]=v}}, bluetooth:{startUartService(){},onBluetoothConnected(f){handlers.connect=f},onBluetoothDisconnected(f){handlers.disconnect=f},onUartDataReceived(_,f){handlers.receive=f},uartReadUntil(){return incoming},uartWriteString(s){sent.push(s.trim())}},input:{runningTime(){return now},onButtonPressed(b,f){handlers[b]=f}},basic:{showIcon(){},forever(f){handlers.tick=f},pause(){}},serial:{delimiters(){return '\n'}},Delimiters:{NewLine:10},Button:{A:'A',B:'B'},IconNames:{Yes:1,SmallDiamond:2},parseInt};
let source=fs.readFileSync('Firmware/main.ts','utf8').replace(/: string/g,'').replace(/: number/g,'');
vm.runInNewContext(source,ctx);
const command=s=>{incoming=s;handlers.receive();return sent.at(-1)};
const stopped=()=>assert.deepEqual(motors,{1:0,3:0});
stopped(); handlers.connect(); stopped();
assert.equal(command('HELLO'),'ROVER:1');
assert.equal(command('D:100:100'),'ERR:DISARMED'); stopped();
assert.equal(command('ARM'),'OK:ARM');
assert.equal(command('D:80:-90'),'OK:D'); assert.deepEqual(motors,{1:80,3:-90});
now=400;handlers.tick();assert.equal(motors[1],80);
now=401;handlers.tick();stopped();assert.equal(sent.at(-1),'SAFE:TIMEOUT');
assert.equal(command('D:80:80'),'ERR:DISARMED');
for(const bad of ['D:161:0','D:-161:0','D:NaN:1','D:12junk:3','D::4','D:-:3','D:1:2:3','D:1.2:0']) {
 command('ARM');command('D:80:80');command(bad);stopped();assert.ok(sent.at(-1).startsWith('ERR:'));
 assert.equal(command('D:80:80'),'ERR:DISARMED');
}
for(const stop of ['STOP','HELLO','UNKNOWN']) {command('ARM');command('D:80:80');command(stop);stopped()}
for(const button of ['A','B']){command('ARM');command('D:80:80');handlers[button]();stopped();assert.equal(sent.at(-1),'SAFE:BUTTON')}
command('ARM');command('D:80:80');handlers.disconnect();stopped();handlers.connect();assert.equal(command('D:80:80'),'ERR:DISARMED');
command('ARM');command('D:0:0');stopped();
assert.ok(sent.every(s=>Buffer.byteLength(s+'\n')<=20));
console.log('PASS: boot/disconnect stop, arming, motor mapping, 400ms watchdog, strict parsing, limits, button stops, release-to-zero, protocol size');
