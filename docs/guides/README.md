# ThinkerLab rover guides

Three illustrated, standalone 12-page guides for app 1.7.2 (build 15):

- [Simple joystick](ThinkerLab_Rover_01_Joystick.pdf)
- [Hand gesture control](ThinkerLab_Rover_02_Gesture.pdf)
- [Voice control](ThinkerLab_Rover_03_Voice.pdf)

Each covers parts, a custom three-wheel chassis, M1/M3 wiring, firmware flashing, iPhone installation with Xcode, calibration, controls, technology and troubleshooting. The chassis drawings are illustrative, not a verified kit-specific bill of materials. A suitable front caster may need to be added.

[Ready-to-flash firmware](../../downloads/README.md)

## Rebuild the PDFs

From the repository root, with Python 3 and ReportLab installed:

```sh
python3 -m pip install reportlab
python3 docs/guides/source/build_guides.py --output-dir docs/guides
```

The generator also writes `layout-checks.json` beside itself for layout QA. Render PDFs with Poppler and visually inspect them after editing.

## Credits and validation

ThinkerLab logo: https://www.thinkerlab.com.au/thinkerlab-logo-horizontal-transparent.png

Yahboom board/motor photo: https://www.yahboom.net/public/upload/upload-html/1753441202/2.APP%20control.html

Kit documentation: https://www.yahboom.net/study/buildingbit-super-kit

App screenshots are simulator captures; labelled diagrams were created for these guides. Refer to the manufacturer for your exact board revision. Source and Apple documentation links are included in each PDF.

All 36 pages were rendered and visually reviewed. App source snapshot: a71c3e5. Existing rover joystick/gesture operation and basic voice commands were user-confirmed; the latest polite-phrase voice fix passed automated tests and still needs physical user confirmation. See HANDOVER.md in the repository root for development details.
