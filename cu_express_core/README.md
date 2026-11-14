# CU Express Core

Connect a VESC Express T already wired to your bike's CAN bus to a Charged Up
CUP-3.5 screen. This package runs on the Express T using stock firmware.

## What you need

- **VESC Express T** running stock **VESC Express 7.00**.
- CAN wiring to the motor controller, with matching baud rates and a different
  CAN ID for each device. UART-only wiring is not supported.
- A CUP-3.5 screen on the same radio channel. The default is channel 1.

## Install and connect

1. Connect VESC Tool to the Express T and confirm its hardware name.
2. Back up any existing package, then install `cu_express_core.vescpkg` through
   **VESC Packages**.
3. Power-cycle the Express T. Leave automatic controller discovery on for a
   single-controller bike.
4. Find and select the link on the CUP-3.5. The link remembers the paired screen.
5. Open the package page to check the controller and screen connections.

Connection changes take effect after a power cycle. On a dual-controller bike,
check both selected CAN IDs. To pair a different screen, turn the old screen
off and use **Forget paired screen**.

## Controller features

Express Core carries controller telemetry, mode commands, kids limits,
Wheelie status and supported setup commands between the controller and screen.
It can also carry telemetry from a compatible CAN BMS.

CU Core ESC or CU Wheelie runs separately on the motor controller. That package
provides its mode and setup features; Express Core supplies the connection.
Standard VESC telemetry is available without either controller package.

Express Core does not add an IMU, light outputs, ANT reader or IO-hat controls.

## Connection problems

Check CAN wiring, power, baud rate and device IDs in VESC Tool. The screen and
Express T must use the same radio channel. A Wi-Fi station connection can
change the Express T's channel; disconnect it while using the screen link.

If the link remembers another screen, turn that screen off and forget its
pairing before trying again.

## Build from source

Requires Python 3.9+, Make and VESC Tool.
Build from the root of the full repository so the shared `tools/` folder is
included:

```sh
make -C cu_express_core VESC_TOOL=/path/to/vesc_tool
```

Output: `cu_express_core/cu_express_core.vescpkg`. See the
[build options](https://github.com/chargedup3d/vesc-packages#build-from-source)
for tool paths, versioning and archive builds.

## License

GPL-3.0-or-later. See `LICENSE.txt` and `NOTICE.txt` for terms and credits.
