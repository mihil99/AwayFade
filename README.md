# AwayFade

AwayFade is a small native macOS menu-bar utility that lowers the volume of connected Bluetooth headphones along a four-point proximity curve. It uses Bluetooth signal strength, not claimed physical distance.

## Included in this MVP

- Two to eight editable, labelled curve points; rename them by clicking their names in the collapsible Point details section
- Actively refreshed Bluetooth RSSI readings, with the cached IOBluetooth value retained only as a labelled fallback
- Relative volume at each curve point, with smooth interpolation between them
- Three-reading median smoothing, a 2 dBm deadband, and a two-sample settling delay before changing real volume
- A live curved proximity graph with draggable signal-and-volume control points, plus add/remove controls
- Eight-second delayed calibration followed by four seconds of sampling
- Smooth 1.6-second volume fades
- A simulation slider for testing without walking away
- Safety checks that only change the captured output device when it still matches the selected headphones
- Restoration of the original reference volume when fading is switched off

## Run the packaged app

Open `AwayFade.app`. It runs only in the menu bar. macOS may ask for Bluetooth access the first time it reads signal strength.

1. Connect the AirPods to the Mac and select them as its audio output.
2. Open AwayFade from the menu bar and select the AirPods.
3. Set the Mac to the loudest indoor volume you want, then turn AwayFade on.
4. Adjust the four volume percentages.
5. For calibration, click **Calibrate** beside a level and walk to that position during the eight-second countdown. A beep marks the start of the four-second sample.

The status card labels the sensor source **Live**, **Cached fallback**, or **Unavailable**. Testing → **Use simulated signal** still demonstrates the complete level and volume behaviour.
The simulation slider follows the graph: **Near** is on the left and **Far** is on the right.
Simulation bypasses real-world smoothing so the graph and selected level respond immediately. The main **Fading** toggle must also be on for simulation to change actual output volume.

## Build from source

Requirements: macOS 14 or newer and Xcode command-line tools.

```sh
./Scripts/package-app.sh
```

The script builds a release executable, assembles `AwayFade.app`, and applies an ad-hoc signature. This personal build is intentionally not App-Sandboxed because the live sensor invokes Apple’s `/usr/sbin/system_profiler`; a sandboxed build can only see the commonly frozen cached RSSI value. AwayFade contains no networking or general file-access code.

Run tests with:

```sh
swift test --scratch-path ../../work/AwayFadeTests
```

## Current limitations

- RSSI responds to walls, body position, interference, and which earbud maintains the radio link. Calibration is intentionally local to one room/route.
- Live sampling invokes macOS’s Bluetooth system profile roughly once per second because the direct IOBluetooth property is commonly cached for connected AirPods.
- The app changes the whole selected output volume, including alerts—not one media application.
- The reference volume is captured when AwayFade is enabled. If you manually change volume while it is running, use **Use current volume as reference**.
- The app cannot extend Bluetooth range.
