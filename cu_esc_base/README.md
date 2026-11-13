# CU Core ESC

Power modes and controller setup for a Charged Up screen or iOS app. Install
CU Core ESC on the **motor controller**, running **VESC firmware 7.00**.

CU Core ESC and CU Wheelie replace one another. For a stock Express T connected
by CAN, install Express Link on the Express T as well.

## Install

1. Connect VESC Tool to the motor controller and confirm firmware 7.00.
2. Back up the motor configuration and existing package.
3. Install `cu_esc_base.vescpkg` through **VESC Packages**.
4. Power-cycle the controller so CU Core ESC loads its original limits.
5. Check wheel diameter, motor poles and gearing, then set your mode limits.

CU Core ESC starts in Neutral until a display selects a mode. Neutral blocks drive
current and retains braking.

## Power modes

The CUP-3.5 screen, Charged Up iOS app and VESC Tool package page edit the same
saved mode table. Power is a percentage of forward motor current. Speed is
stored in km/h and displayed in your selected units. A mode cannot raise the
controller's underlying current or speed limits.

| Mode | Default power | Default speed limit |
| --- | --- | --- |
| Reverse | 50% | 15 km/h |
| 1 | 50% | 20 km/h |
| 2 | 60% | 25 km/h |
| 3 | 100% | 250 km/h |

Mode 3's high default leaves the controller's original speed limit in effect.
Set limits for your vehicle before riding.

Braking cancels cruise. Kids limits and the last applied mode limits stay in
effect if the screen disconnects. Turn kids mode off explicitly to release
its limits. Kids watt limits apply to each controller separately.

## Motor Wizard and calibration

Use the screen's Detection and Setup page through direct controller Bluetooth
or a compatible Charged Up CAN link. Start in Neutral with the motor stopped.
Setup holds drive output until **END**.

Motor Wizard uses VESC Tool's motor-size presets and native controller
measurements. Detection can rotate the motor. Secure it and keep clear before
starting. A successful detection saves the tune after checking the results and
reading the configuration back.

Detection preserves application settings, battery limits, speed settings and
switching frequency. It may lower motor current to the selected preset's
limit, but cannot raise the existing caps. Encoder setups are rejected. A failed
Hall detection does not replace an existing Hall tune with sensorless operation.

**STOP** or a lost setup connection cancels detection and restores the previous
configuration. Measurements may take time to stop; wait for **END**. If
restoration fails, output stays held and **END** retries it.

Motor measurement previews and Hall checks do not save a tune. Throttle/brake
calibration saves the verified endpoints without enabling ADC control. IMU
setup is available when the sensor is present; cart mode hides those options.

## Editing settings in VESC Tool

CU Core ESC applies mode limits as temporary motor settings. Do not save an active
mode or Neutral as the controller's underlying motor configuration.

Before editing or backing up the underlying motor configuration, remove CU Core ESC,
restart the controller and read its settings again. Reinstall CU Core ESC and
power-cycle afterward. Use CU Core ESC's mode editor for ordinary power and speed
changes.

Motor Wizard presets follow [VESC Tool](https://github.com/vedderb/vesc_tool/blob/53dd253c9e3b60a38584d776d4dadcc14b51b0a4/mobile/SetupWizardFoc.qml).
See `LICENSE.txt` for the GPLv3 license and retain the source attribution notices.
