# CU Express Core

The screen-link package for an Express T running Charged Up Link firmware.
The device must report **CU Link** in VESC Tool. For stock VESC Express T 7.00,
use Express Link instead.

Express Core connects a CUP-3.5 screen over ESP-NOW to the motor controller's
CAN bus. CU Core ESC is a separate package on the motor controller.

## Features

- Controller discovery, screen pairing and live telemetry.
- Drive modes, Neutral and kids limits.
- Wheelie status and arm commands when CU Wheelie is installed.
- Setup commands supported by the connected controller and link version.
- Optional CAN lights, tail strip, CAN BMS data and ANT BMS reader.
- A read-only VESC Tool gateway through compatible screen firmware.

This package has no onboard IMU measurement or IO-hat switch/AUX controls.

## Install or update

1. Connect VESC Tool to the Express T and confirm the hardware name **CU Link**.
2. Back up its package and settings.
3. Install `cu_link.vescpkg` through **VESC Packages**, then power-cycle.
4. Check the selected controller, radio channel and paired screen on the
   package page.

When updating the older Charged Up Link package, controller and radio settings,
kids limits, lights, learned modes and the paired screen are copied on first
startup. The copy is checked before the link starts. An interrupted copy
retries on the next startup.

You may need to select the ANT battery again after updating. New ANT selections
are saved.

## License

GPL-3.0-or-later. See `LICENSE.txt` and `NOTICE.txt` for terms and credits.
