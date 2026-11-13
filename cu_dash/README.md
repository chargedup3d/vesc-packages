# CU Dash

The dashboard package for the CUP-3.5 screen. Shows live controller data, with
bike and cart modes, selectable themes, power modes and controller setup.

Get the [CUP-3.5 screen from Charged Up 3D](https://chargedup3d.com/products/bike-e-scooter-advanced-display-3-5).

## Install

Install `cu_dash.vescpkg` on a screen that reports **CUP-3.5** in VESC Tool.
It must already have Charged Up screen firmware and the enlarged Lisp
partition.

Back up the existing package and settings, install the file through
**VESC Packages**, then power-cycle the screen. Updating the package keeps
saved screen settings.

## Connect

Tap **Tap to find a controller** to open Detection and Setup. Connect directly
over controller Bluetooth, or select a Charged Up link on the controller's CAN
bus. Use Express Core for a stock Express T. CU Link, CU IO Link and Express
IMU boards use their matching packages.

Standard VESC telemetry works without a controller package, including the
Flipsky 75100 on firmware 6.00 and 7.00. Power-mode editing and Motor Wizard
require CU Core ESC on a controller running 7.00. Available setup options depend on
the controller package and connection.

## Cart mode and themes

Cart mode starts with the cart theme and hides bike functions such as CU Wheelie and IMU setup. You can choose a different theme and stay in cart mode.

Open Quick Settings to change brightness or Power Modes. Day and night
brightness are saved separately. The toggle in Power Modes shows or hides the
mode button on the live screen.

## Change a mode's power or speed

With CU Core ESC connected, stop and select Neutral. Open **Power Modes**, choose a
mode, then select **POWER** or **SPEED**.

Power is a percentage of forward motor current. Speed uses the screen's MPH
or KPH setting. **SAVE MODE** saves to the controller and confirms its value.
**RELOAD** discards your edits. Save or reload before selecting another field
or mode.

These are the same limits shown in the Charged Up iOS app and CU Core ESC's VESC Tool
page. They cannot raise the controller's underlying limits.

## Setup and help

Detection and Setup includes Motor Wizard, Hall checks and throttle/brake
calibration when supported by the controller and connection. Motor detection
can turn the motor: secure it, keep clear and wait for **END** before leaving
setup.

Tap the help button at the bottom right for common connection and setup questions.

Font credits and license notices are in `FONT-NOTICES.txt`.

## License

GPL-3.0-or-later. See `LICENSE.txt` and `NOTICE.txt` for terms and credits.
