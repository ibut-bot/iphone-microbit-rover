func mix(_ x:Double,_ y:Double,_ swap:Bool=false,_ r1:Bool=false,_ r3:Bool=false)->(Int,Int){RoverMix.motors(x:x,y:y,limit:0.35,swap:swap,reverse1:r1,reverse3:r3)}
assert(mix(0,0) == (0,0)); assert(mix(0.05,0.05) == (0,0))
assert(mix(0,1) == (89,89)); assert(mix(0,-1) == (-89,-89))
assert(mix(1,0) == (89,-89)); assert(mix(-1,0) == (-89,89))
assert(mix(1,0,true) == (-89,89)); assert(mix(0,1,false,true,false) == (-89,89))
for x in stride(from:-1.0,through:1.0,by:0.05){for y in stride(from:-1.0,through:1.0,by:0.05){let v=mix(x,y); assert(abs(v.0)<=89 && abs(v.1)<=89)}}
print("PASS: joystick deadzone, forward/reverse, turns, wheel swap, reversal and speed bounds")
