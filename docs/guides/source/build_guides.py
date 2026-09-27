from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color, white
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.lib.utils import ImageReader
from reportlab.graphics.barcode import qr
from reportlab.graphics.shapes import Drawing
from reportlab.graphics import renderPDF
import math, re, json, argparse

ROOT=Path(__file__).resolve().parent
AS=ROOT/'assets'
parser=argparse.ArgumentParser()
parser.add_argument('--output-dir', type=Path, default=ROOT.parent.parent/'outputs')
OUT=parser.parse_args().output_dir
OUT.mkdir(parents=True, exist_ok=True)
W,H=595.276,841.89
NAVY=HexColor('#002B49'); TEAL=HexColor('#008C95'); GOLD=HexColor('#F6B900'); INK=HexColor('#203747'); GREY=HexColor('#536673'); PALE=HexColor('#EEF6F7'); LINE=HexColor('#DCE5E8'); RED=HexColor('#B72F43')
REPO='https://github.com/ibut-bot/iphone-microbit-rover'
HEX=REPO+'/raw/refs/heads/main/downloads/microbit-rover.hex'
KIT='https://www.yahboom.net/study/buildingbit-super-kit'
BRAND='https://www.thinkerlab.com.au/'
PHOTO='https://www.yahboom.net/public/upload/upload-html/1753441202/2.APP%20control.html'
APPLE='https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices'
DEV='https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device'
ACCT='https://developer.apple.com/help/account/basics/about-your-developer-account'
VISION='https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision'
SPEECH='https://developer.apple.com/documentation/speech/sfspeechrecognizer'
FM='https://developer.apple.com/documentation/foundationmodels'
CHARGE='https://www.yahboom.net/public/upload/upload-html/1753440149/2.7%20Notes%20on%20charging%20and%20battery%20use.html'
styles={}
for n,size,lead,font,col in [('body',10.7,15.3,'Helvetica',INK),('small',8.4,11.5,'Helvetica',GREY),('table',9.8,13.5,'Helvetica',INK),('h2',15,19,'Helvetica-Bold',NAVY),('h3',11,15,'Helvetica-Bold',NAVY),('white',11,16,'Helvetica',white),('code',9,13,'Courier',INK)]:
 styles[n]=ParagraphStyle(n,fontName=font,fontSize=size,leading=lead,textColor=col,spaceAfter=0)
checks=[]
def clean(s):
 return s.replace('—',' - ').replace('–','-').replace('‑','-').replace('’',"'").replace('“','"').replace('”','"').replace('→',' > ').replace('≤','&lt;=').replace('±','+/-')
def p(c,text,x,y,w,sty='body'):
 q=Paragraph(clean(text),styles[sty]);_,h=q.wrap(w,1000);q.drawOn(c,x,H-y-h)
 checks.append((c._pageNumber,y,y+h,text[:50]))
 return y+h

def rect(c,x,y,w,h,fill=PALE,stroke=None,r=12):
 c.setFillColor(fill);c.setStrokeColor(stroke or fill);c.roundRect(x,H-y-h,w,h,r,fill=1,stroke=bool(stroke))
def text(c,s,x,y,size=10,font='Helvetica',col=INK):
 c.setFillColor(col);c.setFont(font,size);c.drawString(x,H-y,clean(s))
def image(c,name,x,y,w,h):
 path=AS/name;im=ImageReader(str(path));iw,ih=im.getSize();scale=min(w/iw,h/ih)
 c.drawImage(im,x+(w-iw*scale)/2,H-y-h+(h-ih*scale)/2,width=iw*scale,height=ih*scale,mask='auto')
def arrow(c,x1,y1,x2,y2,col=TEAL,width=2):
 c.setStrokeColor(col);c.setFillColor(col);c.setLineWidth(width);c.line(x1,H-y1,x2,H-y2)
 a=math.atan2(y2-y1,x2-x1);sz=7
 path=c.beginPath();path.moveTo(x2,H-y2)
 for d in [-.48,.48]: path.lineTo(x2-sz*math.cos(a+d),H-(y2-sz*math.sin(a+d)))
 path.close();c.drawPath(path,fill=1,stroke=0)
def rule(c,y):
 c.setStrokeColor(LINE);c.setLineWidth(.7);c.line(40,H-y,W-40,H-y)
def box(c,title,body,x,y,w,h=None):
 q=Paragraph(clean(body),styles['body']);_,bh=q.wrap(w-28,1000);h=h or bh+52
 rect(c,x,y,w,h);p(c,title,x+14,y+12,w-28,'h3');p(c,body,x+14,y+35,w-28)
 return y+h

def step(c,n,title,body,x,y,w):
 rect(c,x,y,26,26,TEAL,r=8);text(c,str(n),x+8,y+18,11,'Helvetica-Bold',white)
 yy=p(c,title,x+38,y,w-38,'h3');yy=p(c,body,x+38,yy+4,w-38)
 return max(y+30,yy)+15

def bullets(c,items,x,y,w):
 for item in items:
  text(c,'•',x,y+11,11,'Helvetica',TEAL)
  y=p(c,item,x+14,y,w-14)+9
 return y

def table(c,rows,x,y,widths,header=True):
 data=[[Paragraph(clean(str(s)),styles['table'] if len(str(s))>80 else styles['body']) for s in row] for row in rows]
 t=Table(data,colWidths=widths,hAlign='LEFT')
 cmds=[('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),10),('RIGHTPADDING',(0,0),(-1,-1),10),('TOPPADDING',(0,0),(-1,-1),9),('BOTTOMPADDING',(0,0),(-1,-1),9),('LINEBELOW',(0,0),(-1,-1),.5,LINE)]
 if header: cmds += [('BACKGROUND',(0,0),(-1,0),PALE)]
 t.setStyle(TableStyle(cmds));tw,th=t.wrap(sum(widths),1000);t.drawOn(c,x,H-y-th);checks.append((c._pageNumber,y,y+th,'TABLE'));return y+th

def link(label,url): return f'<link href="{url}" color="#008C95"><u>{label}</u></link>'

def qr_code(c,url,x,y,size=70):
 widget=qr.QrCodeWidget(url);b=widget.getBounds();d=Drawing(size,size,transform=[size/(b[2]-b[0]),0,0,size/(b[3]-b[1]),0,0]);d.add(widget);renderPDF.draw(d,c,x,H-y-size)

def header(c,mode,num,title,sub):
 c.setFillColor(white);c.rect(0,0,W,H,fill=1,stroke=0)
 image(c,'thinkerlab-logo.png',40,20,160,41)
 text(c,'ROVER LAB  /  '+mode.upper(),330,44,9,'Helvetica-Bold',TEAL)
 rule(c,76)
 p(c,title,40,95,515,'h2');p(c,sub,40,122,515,'small')
 rule(c,797);text(c,'THINKERLAB  |  Microbit Link 1.7.2  |  27 September 2026',40,814,7.5,'Helvetica',GREY)
 text(c,f'{num:02d} / 12',510,814,8,'Helvetica-Bold',TEAL)
 c.bookmarkPage(f'page{num}');c.addOutlineEntry(title,f'page{num}',0,False)

def rover(c,x,y,w,h,stage=3):
 # Diagram uses a consistent top-down plan; labels are schematic, not board pin locations.
 sx=w/515;sy=h/285
 def X(a):return x+a*sx
 def Y(a):return y+a*sy
 def R(a,b,d,e,color):rect(c,X(a),Y(b),d*sx,e*sy,color,r=6)
 R(137,57,240,185,HexColor('#BFE2E5'))
 for xx in [148,358]:
  R(xx,65,9,165,TEAL)
  for yy in range(77,231,20):
   c.setFillColor(white);c.circle(X(xx+4.5),H-Y(yy),2*sx,fill=1,stroke=0)
 R(146,82,221,10,TEAL);R(146,220,221,10,TEAL)
 if stage>=2:
  R(110,164,40,65,RED);R(365,164,40,65,RED)
  R(77,159,30,75,NAVY);R(409,159,30,75,NAVY)
  R(239,38,38,46,NAVY)
  c.setStrokeColor(TEAL);c.setLineWidth(3);c.arc(X(226),H-Y(97),X(290),H-Y(23),0,180)
 if stage>=3:
  R(194,97,126,104,NAVY);R(224,128,64,54,HexColor('#70B4CF'))
  R(202,92,110,32,HexColor('#111C24'))
  for a in range(5):
   for b in range(5):
    c.setFillColor(RED);c.circle(X(235+a*6),H-Y(98+b*4),1*sx,fill=1,stroke=0)
  text(c,'Super:bit',X(228),Y(192),8*sx,'Helvetica-Bold',white)
  arrow(c,X(186),Y(185),X(142),Y(185),GOLD);arrow(c,X(326),Y(185),X(372),Y(185),GOLD)
 text(c,'FRONT',X(234),Y(13),10*sx,'Helvetica-Bold',TEAL)
 arrow(c,X(257),Y(35),X(257),Y(19))
 if stage>=2:
  text(c,'LEFT MOTOR',X(48),Y(257),9*sx,'Helvetica-Bold',NAVY);text(c,'M1',X(81),Y(273),11*sx,'Helvetica-Bold',TEAL)
  text(c,'RIGHT MOTOR',X(383),Y(257),9*sx,'Helvetica-Bold',NAVY);text(c,'M3',X(412),Y(273),11*sx,'Helvetica-Bold',TEAL)
  p(c,'Free-spinning<br/>front caster',X(325),Y(22),140*sx,'small')
  arrow(c,X(323),Y(44),X(281),Y(57),GREY,1)
 if stage>=3:
  p(c,'micro:bit<br/>LED face forward',X(12),Y(80),125*sx,'small');arrow(c,X(116),Y(99),X(200),Y(104),GREY,1)

def wheel_diagram(c,x,y,w):
 for i,(title,l,r) in enumerate([('FORWARD',-1,-1),('REVERSE',1,1),('TURN LEFT',1,-1),('TURN RIGHT',-1,1)]):
  bx=x+i*w/4;rect(c,bx+3,y, w/4-8,118,PALE)
  rect(c,bx+34,y+43,46,48,HexColor('#BFE2E5'),r=4)
  for ox,d in [(26,l),(89,r)]:
   rect(c,bx+ox-5,y+51,10,33,NAVY,r=3)
   arrow(c,bx+ox,y+(47 if d==1 else 88),bx+ox,y+(91 if d==1 else 44),TEAL,1.7)
  text(c,title,bx+12,y+22,8,'Helvetica-Bold',NAVY)

def flow(c,labels,x,y,w):
 gap=14;bw=(w-gap*(len(labels)-1))/len(labels)
 for i,(title,body) in enumerate(labels):
  bx=x+i*(bw+gap);rect(c,bx,y,bw,95,PALE);p(c,title,bx+10,y+12,bw-20,'h3');p(c,body,bx+10,y+38,bw-20,'small')
  if i<len(labels)-1:arrow(c,bx+bw+2,y+48,bx+bw+gap-2,y+48,TEAL,1)

def hand_panel(c,x,y,w,h,pinched=False,dx=0,dy=0):
 rect(c,x,y,w,h,PALE)
 cx=x+w/2;cy=y+h/2+6;r=min(w,h)*.30
 c.setStrokeColor(LINE);c.setLineWidth(1.5);c.circle(cx,H-cy,r,fill=0,stroke=1)
 c.setDash(3,3);c.circle(cx,H-cy,r*.28,fill=0,stroke=1);c.setDash()
 # Anatomical schematic: palm, index and thumb meet at joystick centre.
 col=HexColor('#DFC1A2');c.setStrokeColor(col);c.setLineWidth(13);c.setLineCap(1)
 px=cx+dx;py=cy+dy
 c.line(px-30,H-(py+55),px-25,H-(py+23));c.line(px-25,H-(py+23),px-10,H-(py-5 if pinched else py-28))
 c.line(px+18,H-(py+53),px+24,H-(py+20));c.line(px+24,H-(py+20),px+2,H-(py-5 if pinched else py+3))
 c.setLineWidth(23);c.line(px-13,H-(py+50),px+9,H-(py+47));c.setLineCap(0)
 c.setFillColor(TEAL if pinched else GREY);c.circle(px-4,H-(py-5),5,fill=1,stroke=0)
 if pinched:
  c.setStrokeColor(TEAL);c.setLineWidth(2);c.circle(cx,H-cy,r,fill=0,stroke=1)

def common(c,mode,title,num):
 if num==1:
  header(c,mode,1,title,'A complete, illustrated build-and-drive guide for the three-wheel ThinkerLab rover.')
  rect(c,40,161,515,62,NAVY)
  p(c,'Two rear drive wheels. One free-spinning front support. One iPhone.',56,175,480,'white')
  rover(c,40,241,515,285)
  p(c,'Layout illustration - not a parts-scale drawing. View from above; front is toward the LED face.',40,532,515,'small')
  p(c,'Your route from box to moving robot',40,570,515,'h2')
  table(c,[['BUILD','INSTALL','DRIVE'],['Parts + chassis\nPages 2-4','Firmware + iPhone app\nPages 5-6','Connect + your control mode\nPages 7-10']],40,600,[172,172,171])
  box(c,'Before you start','Use a Mac with Xcode and a micro:bit V2. This is a source-installed iPhone app, not an App Store download. Start with the wheels lifted.',40,693,515)
 elif num==2:
  header(c,mode,2,'01 / Gather your parts','A stable rover starts with the correct motors, connectors and a supported phone.')
  rows=[['Quantity','What you need'],['1','Yahboom Building:bit Super Kit / Super:bit board, plus a micro:bit V2. Check which pieces your kit edition includes.'],['2 + 2','Two red DC drive motors and two matching wheels. Use equal wheel diameters.'],['1','A free-spinning front wheel in a swivel fork (caster), or a ball caster with a compatible bracket. Add one if your kit lacks it.'],['As needed','Rigid beams/base plate, cross-braces, axles/bushes and compatible pins or fasteners. No soldering is required for the standard connectors.'],['1 set','The correct Super:bit battery and its approved charging arrangement; data cables for micro:bit and iPhone; a stable phone stand.'],['1 each','Mac, Apple Account and iPhone. Internet is needed for software downloads/signing.']]
  y=table(c,rows,40,160,[68,447])
  y=box(c,'Software and compatibility','These guides target app <b>1.7.2 (build 15)</b>, built with Xcode 26.5 and tested on iPhone 17 Pro / iOS 26.6. The project targets iOS 17+, but older devices have not been validated. Use Xcode 26 or newer with an SDK/device-support version compatible with your phone.',40,y+18,515)
  p(c,{'Joystick':'Joystick needs Bluetooth only. No camera, speech model or Apple Intelligence is needed to drive.','Gesture':'Gesture control needs a front camera. Dual-camera recording additionally needs a supported MultiCam iPhone. Apple Intelligence is not required.','Voice':'Voice needs microphone and on-device English (Australia) speech recognition availability. Flexible AI parsing additionally needs iOS 26+ and an available Apple Intelligence model; basic commands do not.'}[mode],40,y+16,515)
 elif num==3:
  header(c,mode,3,'02 / Build a rigid three-wheel chassis','A custom triwheel layout using compatible kit parts; exact brick lengths can vary.')
  rover(c,40,154,515,240,stage=2)
  y=416
  y=step(c,1,'Make a braced base','Join two parallel beams with front and rear cross-braces. Add a plate or a second brace so the frame cannot twist when you gently flex opposite corners.',40,y,515)
  y=step(c,2,'Fit the rear motors and wheels','Mount one DC motor on each rear side. Keep shafts level, parallel and facing outward. Fit the two drive wheels; leave a small gap so tyres and hubs do not rub on beams.',40,y,515)
  y=step(c,3,'Add the front support','Centre the caster at the front. Fit its fork/axle loosely enough to roll freely but securely enough not to fall out. A swivel or ball caster makes rotation easier; a fixed front wheel may scrub sideways.',40,y,515)
  p(c,'CHECK: all three wheels touch a flat surface; the chassis sits level; rear wheels rotate freely; the caster swivels through a full turn. Adjust bracket height before adding electronics.',40,y+2,515,'h3')
 elif num==4:
  header(c,mode,4,'03 / Mount, connect and power','Turn the board OFF and disconnect charging/USB power before moving connectors.')
  image(c,'yahboom-motors.png',55,151,485,296)
  p(c,'Yahboom reference photo: left motor on M1, right motor on M3. Match the printed labels on your board; this is not a photo of the custom chassis. [2]',40,455,515,'small')
  y=493
  y=step(c,4,'Secure the board and insert micro:bit','Use the Super:bit mounting holes and compatible pins/standoffs. Keep metal away from exposed contacts. Insert the micro:bit fully in the edge connector, oriented as the manufacturer shows; keep its LED face toward your chosen front.',40,y,515)
  y=step(c,5,'Connect the drive motors','Viewed from behind, looking forward: plug the LEFT motor into M1 and RIGHT motor into M3. Use the keyed two-wire plugs without forcing them. Leave M2, M4 and the servo sockets unused. Route leads clear of the wheels.',40,y,515)
  box(c,'Battery and charging','Use only the battery type/polarity specified for your board revision. The pictured board uses one 3.7 V 18650 cell. Charge through the Super:bit charging port, not the micro:bit USB port; do not drive while charging. Keep its switch OFF until testing. [3]',40,y+1,515)
 elif num==5:
  header(c,mode,5,'04 / Put rover firmware on micro:bit','Firmware is the small program that receives Bluetooth commands and controls the motors.')
  flow(c,[('DOWNLOAD','Get the rover HEX from GitHub.'),('COPY','Copy the HEX onto MICROBIT.'),('WAIT','Let flashing finish, then unplug.')],40,163,515)
  y=281
  y=step(c,1,'Download the correct program',f'Open {link("the firmware download",HEX)} and save <b>microbit-rover.hex</b>. Or open {link("GitHub / downloads",REPO+"/tree/main/downloads")} and use the file download button. This replaces the program already on micro:bit. Do not use the vendor demo firmware or the LED-only example.',40,y,515)
  y=step(c,2,'Connect micro:bit to the Mac','Leave motor power off. Connect a USB data cable to the micro:bit itself. Finder should show a drive named <b>MICROBIT</b>. A charging-only cable will not work.',40,y,515)
  y=step(c,3,'Copy and wait','Drag microbit-rover.hex onto MICROBIT. Wait for the transfer and the flashing activity LED to finish. If a FAIL.TXT file appears, read it and retry with a known data cable. The supplied firmware shows a small diamond while disconnected.',40,y,515)
  y=step(c,4,'Disconnect the programming cable','The rover will run wirelessly once its board battery is switched on. A USB cable in the micro:bit may power only the controller; it is not a substitute for the board motor supply.',40,y,515)
  box(c,'Optional: build the HEX from source',f'Install Node.js/npm, download/extract the repository, and run these commands in its folder. The build script uses the MakeCode cloud compiler, so internet is required.<br/><font face="Courier">bash scripts/build-firmware.sh<br/>cp -X .build/microbit-rover.hex /Volumes/MICROBIT/</font><br/>The ready-made HEX is supplied for this guide; no Arduino or ESP32 firmware is needed.',40,y+2,515)
 elif num==6:
  header(c,mode,6,'05 / Install Microbit Link on iPhone','Use your own Apple Account and signing identity. There is no App Store or TestFlight link.')
  y=155
  y=step(c,1,'Get the current source',f'Open {link("the project on GitHub",REPO)}. Choose <b>Code > Download ZIP</b>, then extract it on your Mac. Open <b>MicrobitLink.xcodeproj</b> from the extracted folder. Use version 1.7.2 or later; the older release still has Enable buttons and no voice screen.',40,y,515)
  y=step(c,2,'Set up Xcode signing','Install a compatible Xcode from Apple and open it once to finish setup. In Xcode Settings > Apple Accounts, sign in. Select the blue project, then the MicrobitLink target > Signing & Capabilities. Enable automatic signing and choose your own Team.',40,y,515)
  y=step(c,3,'Choose an app identifier','Replace org.example.microbitlink with a unique identifier such as <b>com.yourname.rover</b>. Keep that identifier for later updates; changing it creates a separate app with separate preferences.',40,y,515)
  y=step(c,4,'Trust and prepare the phone','Connect and unlock iPhone, accept Trust prompts and select it as Xcode\'s run destination. If requested, enable Settings > Privacy & Security > Developer Mode, restart and confirm. Developer Mode may appear only after pairing with Xcode. [4,5]',40,y,515)
  y=step(c,5,'Build, install and open','Click the Run triangle (Command-R). Wait for a successful build and installation. Follow any developer-trust prompt on iPhone; then open <b>Microbit Link</b> and allow Bluetooth. The app screen is titled <b>Microbit Rover</b>. [4]',40,y,515)
  box(c,'Keep the installation working','A free Personal Team installation expires after seven days; rebuild and reinstall with the same identifier to renew it. If Xcode cannot support your iOS version, update Xcode/macOS as required before retrying. An iPhone alone cannot perform this source-install workflow. [6]',40,y+1,515)
 elif num==7:
  header(c,mode,7,'06 / Connect and check wheel direction','Do this once with joystick control before trying gestures or speech.')
  image(c,'joystick.png',40,155,212,461)
  p(c,'Actual app UI in the iPhone simulator. Bluetooth is unavailable there; your physical phone shows nearby boards after scanning.',40,625,212,'small')
  y=157
  y=step(c,1,'Lift the drive wheels','Support the chassis securely so both rear wheels are off the table. Switch on the Super:bit battery supply.',272,y,283)
  y=step(c,2,'Connect inside the app','Tap Find micro:bit, then select your board. Wait for Connected - controls ready. Connect in this app, not the iPhone Bluetooth Settings list.',272,y,283)
  y=step(c,3,'Try a tiny forward touch','Select Joystick and use the default 35% limit. Touch briefly above centre, then release. Both wheels should drive toward the marked front.',272,y,283)
  y=step(c,4,'Correct the mapping','Tap STOP > Wheel setup. Keep “M1 is the right wheel” OFF for M1-left/M3-right. Reverse only a motor that turns backward. Tap Done and test again.',272,y,283)
  box(c,'Pass this check before floor driving','Release stops both wheels. Left/right rotate the expected way. STOP and either micro:bit button stop movement. A new touch is needed after Stop. There is no separate Enable step: the app handles ARM when fresh input arrives.',40,680,515)


def mode_page8(c,mode):
 header(c,mode,8,'07 / '+{'Joystick':'Drive with your thumb','Gesture':'Drive with a pinch','Voice':'Drive with your voice'}[mode], 'Start on a clear floor at low speed; keep STOP and the board power switch accessible.')
 if mode=='Joystick':
  wheel_diagram(c,40,156,515)
  y=295
  for n,title,body in [(1,'Touch and hold','Choose Joystick. Touch near the centre and keep your finger on the screen.'),(2,'Move in the direction you want','Slide up to go forward or down to reverse. Slide sideways at the centre to rotate. Slide diagonally to combine forward/reverse with a turn.'),(3,'Choose the amount of movement','Small displacement gives less output. More displacement gives more output up to the Speed limit. The control has a small centre dead zone.'),(4,'Release to stop','Lift your finger to send zero motor output. The joystick springs back to centre. Tap the red STOP button to cancel and disarm; use a fresh touch to resume.'),(5,'Practice before increasing speed','Try forward for one second, release, reverse briefly, release, then a small turn each way. Stop before changing the speed slider or wheel setup.')]:y=step(c,n,title,body,40,y,515)
 elif mode=='Gesture':
  for i,(label,pinch,dx,dy) in enumerate([('1  OPEN',False,0,0),('2  PINCH CENTRE',True,0,0),('3  MOVE PINCH',True,0,-24)]):
   xx=40+i*175;hand_panel(c,xx,156,165,162,pinch,dx,dy);text(c,label,xx+12,335,9,'Helvetica-Bold',TEAL)
  p(c,'Illustrations show thumb/index placement; the app uses live camera landmarks, not these drawings.',40,349,515,'small')
  y=382
  for n,title,body in [(1,'Set the phone upright','Place it on a stable stand with the front camera facing you. In the connected app, choose Hand control and allow Camera access. Keep one hand clearly lit and in frame.'),(2,'Open, then grab the centre','Separate thumb and index. Pinch their tips together inside the dashed centre circle and hold for about 0.15 seconds. Green means the joystick has been grabbed.'),(3,'Move the held pinch','Move UP for forward, DOWN for reverse, LEFT/RIGHT to turn. Move diagonally to steer while moving. Return to the centre for zero output.'),(4,'Let go to stop','Open the pinch or remove the hand. Lost/uncertain fingertip tracking stops movement. After STOP, open your hand and make a fresh centre pinch to resume.')]:y=step(c,n,title,body,40,y,515)
 else:
  image(c,'voice.png',40,153,205,449)
  p(c,'Actual 1.7-series simulator UI. The phone reports its own speech/model availability.',40,611,205,'small')
  y=154
  for n,title,body in [(1,'Open Voice control','Connect the rover first, then tap Voice control on the main screen.'),(2,'Start listening','Tap Start listening and allow Microphone and Speech Recognition. Keep the phone unlocked on this screen.'),(3,'Say one complete command','Say “Rover, forward” and pause briefly. Read Heard and the accepted action. Movement ends automatically after five seconds.'),(4,'Turn or stop','Say “Rover, right” for a one-second rotation. Say “Stop” to cancel immediately when recognised. No Enable button is needed for the next fresh command.')]:y=step(c,n,title,body,268,y,287)
  box(c,'Try this sequence','“Rover, forward” > wait for it to stop > “Rover, left” > “Rover, right” > “Stop” > “Rover, back”. Begin with wheels lifted. A new direction replaces the current action; phrases are not queued.',40,693,515)

def mode_page9(c,mode):
 header(c,mode,9,'08 / Understand the technology','The iPhone interprets your input. The micro:bit runs the motor program.')
 label={'Joystick':('TOUCH','SwiftUI reads the joystick displacement.'),'Gesture':('CAMERA','Apple Vision finds thumb/index landmarks.'),'Voice':('MICROPHONE','Apple Speech transcribes English on-device.')}[mode]
 flow(c,[label,('IPHONE','Checks input and mixes left/right motor values.'),('BLUETOOTH','Sends commands and waits for acknowledgements.'),('ROVER','micro:bit + Super:bit drive M1 and M3.')],40,160,515)
 wheel_diagram(c,40,281,515)
 y=426
 tech={
 'Joystick': [('Differential drive','There is no steering servo. Equal wheel output moves straight. Different outputs make an arc; opposite directions rotate on the spot. The front caster simply follows.'),('How the app mixes motion','The joystick provides forward and turn values. The app combines them into left = forward + turn and right = forward - turn, then applies limits and the saved wheel swaps/reversals.'),('Why your thumb controls speed','The centre dead zone avoids accidental creep. Outside it, displacement scales the output. The slider selects 20-60% of the driver scale, defaulting to 35%; this is not a measured vehicle speed.')],
 'Gesture':[('Landmarks, not an AI chat model','Apple Vision detects hand joints in each camera image. This app mainly uses thumb/index tips and index-finger joints. It tracks the midpoint of the pinched tips as a virtual joystick. [7]'),('Grab before moving','An open hand prepares the gesture gate. A pinch held in the centre for 150 ms grabs the control. The 28% centre dead zone helps keep a centred pinch stationary; hand driving is capped at 35%.'),('Lost fingertips mean zero movement','Brief scale smoothing can tolerate an obscured knuckle, but live fingertip positions are still required. A separate 300 ms camera-stall check stops driving if callbacks stop. Camera processing stays on iPhone.')],
 'Voice':[('Speech recognition and intent are separate','Apple Speech converts microphone audio into words locally. A strict parser handles directions and polite can/could/would/will-you forms. Stop words are checked in partial transcripts without waiting for AI. [8]'),('Apple Intelligence is optional','If available on iOS 26+, the local Foundation Models model can classify flexible wording. The app still requires one explicit direction and the Rover prefix; AI cannot invent power, duration or a route. [9]'),('Bounded actions, no old command queue','Forward/reverse last five seconds; turns one second. “A little” shortens movement. The app consumes each transcript segment once. New speech or Stop invalidates pending AI; results older than three seconds are discarded.')]
 }
 for title,body in tech[mode]:y=p(c,title,40,y,515,'h3');y=p(c,body,40,y+5,515)+17
 box(c,'The stop chain','The app sends motor updates at 10 Hz, with one outstanding reply. A reply timeout around 350 ms triggers Stop/disconnect. Firmware separately disarms after 400 ms without a valid drive update. These are software checks; wheels can coast, and they do not detect obstacles.',40,y,515)

def mode_page10(c,mode):
 header(c,mode,10,'09 / '+{'Joystick':'Practise, tune and explore','Gesture':'Record and improve your gestures','Voice':'Your voice command reference'}[mode], 'Use short, repeatable trials so you can tell what changed.')
 if mode=='Voice':
  rows=[['Say this','Expected action'],['Rover, forward / go forward','Forward for 5 seconds'],['Rover, back / reverse / back up','Reverse for 5 seconds'],['Rover, left / turn left','Rotate left for 1 second'],['Rover, right / turn right','Rotate right for 1 second'],['Rover, can you turn right a little','Rotate right for 0.5 seconds'],['Rover, turn left a little','Rotate left for 0.5 seconds'],['Rover, back up a little','Reverse for 1 second'],['Stop / halt / freeze / cancel','Cancel movement; no Rover prefix needed']]
  y=table(c,rows,40,156,[306,209])
  y=p(c,'What the screen tells you',40,y+22,515,'h2')
  y=bullets(c,['<b>Heard:</b> what speech recognition transcribed, not proof that a command was accepted.','<b>Action + seconds:</b> the interpreted direction and bounded duration. M1/M3 show requested outputs; the reply shows what the rover reported.','<b>Interpreting on iPhone:</b> optional AI is working. Use a simpler command if it times out.','One direction per phrase. Requests for angles, distances, custom times, conditions or multiple actions are rejected. “Turn 90 degrees” is not supported.'],40,y+10,515)
  p(c,'Voice output is capped at 25% (or a lower saved limit). A half-second turn may be small on a grippy surface. First compare “Rover, right” with “Rover, right a little”; do not assume a recognised phrase proves the wheels turned.',40,y+3,515,'small')
 elif mode=='Gesture':
  image(c,'gesture.png',40,156,207,420)
  p(c,'Actual simulator view of the in-app 3D gesture guide. It is available without a rover connection.',40,586,207,'small')
  y=156
  for n,title,body in [(1,'Learn the gesture','Tap the hand icon for the animated guide. Opening it stops the rover and pauses the camera. Close it, open your hand and make a fresh centre pinch.'),(2,'Set up both views','Point the front camera at your hand and the rear camera toward the rover. The lower-right inset shows the rear view.'),(3,'Record only if you want to','Tap Record; allow Microphone and Photos when asked. Recording starts with the rover stopped. Use a fresh pinch to drive.'),(4,'Finish and retrieve the clip','Tap Stop recording and wait for saving. Find the MP4 in Photos or Files > On My iPhone > Microbit Link. Use the Recordings list to share or retry a Photos save.')]:y=step(c,n,title,body,268,y,287)
  box(c,'Improve recognition','Use even light and a plain background. Keep thumb/index tips and the index knuckle visible, with only one hand in frame. Start at centre; moving an already-pinched hand in from the side will not grab. No stale fingertip position is reused to keep driving.',40,690,515)
 else:
  y=163
  for n,title,body in [(1,'Build a release habit','Mark a short lane with tape. Drive forward for about one second, release, then reverse back. Check that release stops the wheels every time.'),(2,'Compare rotation and an arc','Move sideways from centre to rotate. Now move diagonally forward-right: both motion and turn are combined. Explain why the two wheel outputs differ.'),(3,'Tune one setting at a time','Use STOP before changing speed. Keep wheel reversal consistent with forward direction. A rover that drifts can have unequal friction, battery load or motor performance; there is no encoder feedback to correct it.'),(4,'Run a low-speed course','Use wide turns and soft markers on a level floor. Do not use table edges, stairs or people as obstacles. The rover has no automatic obstacle avoidance.'),(5,'Switch to another control mode','Stop, then choose Hand control or Voice control. The same firmware and wheel settings are reused; there is no need to rebuild the rover or reflash between modes.')]:y=step(c,n,title,body,40,y,515)
  wheel_diagram(c,40,y+4,515)
  p(c,'Challenge: predict the sign of M1 and M3 before each turn. Then compare your prediction with the app display.',40,y+140,515,'h3')

def mode_page11(c,mode):
 header(c,mode,11,'10 / Troubleshoot in the right order','Stop first. Check the visible evidence before changing wiring or settings.')
 rows=[['Symptom','Check / next action'],['No MICROBIT drive','Try a known USB data cable and another port. Connect to micro:bit, not the board charging port. Check FAIL.TXT after a failed flash.'],['Xcode will not install','Unlock/trust the phone; select the correct device and your own Team/unique bundle ID. Update Xcode if the phone OS is unsupported. Renew an expired Personal Team install.'],['No rover found','Switch on the board; allow Bluetooth in iPhone Settings; scan in Microbit Link. Disconnect other clients. Reflash the rover HEX if vendor firmware is still installed.'],['Connected but motors do not run','Check the Super:bit switch, charged correct battery, M1/M3 connectors and wheel clearance. USB in micro:bit alone may not supply the motors. Test joystick first.'],['Directions are wrong','STOP > Wheel setup. Confirm M1-left/M3-right. Reverse only the motor that is backward. Swap wheels only if physical left/right really are exchanged.']]
 if mode=='Voice':rows += [['Heard changes, but no motion','Read the exact Heard text and action/status. Start with “Rover, right”. Version 1.7.2 directly accepts “Rover, can you turn right a little”. A phrase without Rover is ignored except Stop words.'],['No speech / AI unavailable','Check microphone and speech permissions. On-device English recognition must be available. Apple Intelligence is optional for basic commands. Pause/start listening after an interruption.'],['A little turn is barely visible','Compare the one-second turn with the half-second turn, wheels lifted first. Check requested M1/M3 values and tyre/caster friction. Output percentage is not guaranteed torque.']]
 elif mode=='Gesture':rows += [['Pinch does not grab','Open thumb/index first. Put their pinch midpoint inside the dashed centre and hold 0.15 seconds. Use one well-lit hand; keep the fingertip landmarks visible.'],['Stops while hand looks steady','Try clearer lighting and bring the hand into frame. Lost tips or a stalled camera deliberately stop movement. Re-open and pinch at centre; do not disable these checks.'],['Recording missing / no rear view','Confirm MultiCam support and camera/microphone permission. Check the frame counter. Stop and wait for save; recover the clip from Files or the Recordings list.']]
 else:rows += [['Stops unexpectedly','Read the rover reply. SAFE:BUTTON means a physical stop; SAFE:TIMEOUT means updates stopped. Reply timeout needs reconnecting. Start again with fresh input, not a held old touch.'],['Turns poorly on the floor','Check caster swivel, rubbing tyres, level chassis and battery. Test the same input with wheels lifted. A stalled motor should not be left powered.'],['Cannot move after STOP','Lift your finger and make a new touch. Stop intentionally invalidates the old held gesture. A dropped Bluetooth connection still needs reconnecting.']]
 y=table(c,rows,40,158,[150,365])
 p(c,'If the problem remains: record the app version, exact status/reply, control mode, motor values, and whether the wheels moved while lifted. Share a wiring photo showing M1/M3 labels and describe one repeatable test.',40,y+19,515,'small')

def mode_page12(c,mode):
 header(c,mode,12,'Keep this page beside the rover','Session checklist, recovery actions and source links.')
 y=158
 y=box(c,'Every session','1. Check wheels, loose leads and battery.  2. Connect in Microbit Link.  3. Test a short movement and Stop with wheels lifted.  4. Put the rover on a clear floor.  5. Keep the app foreground and watch the rover.  6. Finish with STOP, switch off board power, then store safely.',40,y,515)
 y=box(c,'Know how to stop','Joystick: release. Gesture: open pinch or remove hand. Voice: say Stop, or use the screen if speech is delayed. Red STOP and either micro:bit button cancel movement. If software is unresponsive, switch off board motor power. Nothing here senses a cliff or obstacle.',40,y+14,515)
 p(c,'Downloads and references',40,y+30,400,'h2')
 qr_code(c,REPO,472,y+22,74)
 yy=y+63
 refs=[('[1] Source, app and firmware',REPO),('[2] Yahboom kit and motor wiring',KIT),('Yahboom M1/M3 photo source',PHOTO),('[3] Board charging instructions',CHARGE),('[4] Apple: run on a physical device',APPLE),('[5] Apple: Developer Mode',DEV),('[6] Apple: Personal Team and renewal',ACCT)]
 if mode=='Gesture':refs += [('[7] Apple: Vision hand pose',VISION)]
 if mode=='Voice':refs += [('[8] Apple: speech recognition',SPEECH),('[9] Apple: Foundation Models',FM)]
 refs += [('ThinkerLab',BRAND)]
 for label,url in refs:yy=p(c,link(label,url),40,yy,415,'small')+8
 yy=p(c,'GitHub: github.com/ibut-bot/iphone-microbit-rover<br/>Kit: yahboom.net/study/buildingbit-super-kit<br/>Brand: thinkerlab.com.au',40,yy+8,515,'small')
 p(c,'Edition notes: app 1.7.2 / build 15, source snapshot a71c3e5. Joystick and gesture use were confirmed on the existing rover. Voice forward and ordinary right-turn were confirmed; the latest polite-phrase fix passed automated tests and still needs user confirmation. Triwheel drawings are a proposed custom layout, not a verified kit bill of materials.',40,yy+14,515,'small')
 p(c,'Image credits: ThinkerLab logo from its website; motor/board photograph from Yahboom. App screenshots are simulator captures. All labelled chassis, control and data-flow diagrams were created for these guides. Refer to the linked manufacturer instructions for your exact board revision.',40,741,515,'small')

for mode,title,name in [('Joystick','Build a joystick-controlled rover','ThinkerLab_Rover_01_Joystick.pdf'),('Gesture','Build a gesture-controlled rover','ThinkerLab_Rover_02_Gesture.pdf'),('Voice','Build a voice-controlled rover','ThinkerLab_Rover_03_Voice.pdf')]:
 c=canvas.Canvas(str(OUT/name),pagesize=(W,H));c.setTitle(title);c.setAuthor('ThinkerLab');c.setSubject('micro:bit V2 + Yahboom Super:bit + iPhone - end-to-end guide')
 for num in range(1,13):
  if num<=7: common(c,mode,title,num)
  elif num==8:mode_page8(c,mode)
  elif num==9:mode_page9(c,mode)
  elif num==10:mode_page10(c,mode)
  elif num==11:mode_page11(c,mode)
  else:mode_page12(c,mode)
  c.showPage()
 c.save()
print('Created 3 PDFs')
for pg,start,end,t in checks:
 if end>788: print('OVERFLOW',pg,round(end,1),t)
(ROOT/'layout-checks.json').write_text(json.dumps(checks))
