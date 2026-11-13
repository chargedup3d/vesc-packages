# CU Wheelie

Wheelie assistance for a VESC motor controller. Uses pitch and pitch rate to
reduce throttle as the front rises and apply pull-down current above the
configured ceiling.

Requires **VESC firmware 7.00**, a working IMU and supported ADC throttle/brake
controls. It replaces CU Core ESC on the controller. CU Wheelie does not
include CU Core ESC's editable Power Modes table or Motor Wizard.

## Install and set up

1. Back up the controller's configuration and existing package. Install
   `cu_wheelie.vescpkg` through **VESC Packages**, then power-cycle.
2. Install CU IMU on the matching sensor board and connect it to the same
   CAN bus. Mount the sensor rigidly to the frame.
3. With the bike stopped, Wheelie disarmed and both controls released, connect
   VESC Tool to CU IMU. Open **APPUI → Setup**, select the mount axes and
   press **Save mount**. Hold the bike level and still, then run **Zero Level**.
4. Reconnect to the controller and open **IMU Status**. Check **LEVELED** and
   **CONTROLLER: EXPRESS**, and compare pitch with a level.
5. Check pitch rate: positive while lifting the front, near zero while holding
   it still and negative while lowering it. Zero Level does not correct the
   gyro axes.

Assistance starts disarmed. Check throttle, brake and sensor direction with
the bike secured before riding. Arm from the **Live** tab with both controls
released and the bike upright. Assistance cannot guarantee a maximum angle or
prevent a fall.

## Tuning

Change settings on the **Tune** tab, then press **Write & Save**.

| Setting | What it changes |
| --- | --- |
| Throttle fade start | Angle where throttle reduction begins |
| Balance ceiling | Angle where pull-down current engages |
| Pitch-rate damping | Response to how quickly the nose is moving |
| Max pull-down current | Maximum pull-down demand, from 0 to 1 |
| Gyro low-pass | Smoothing of the pitch-rate signal |

Below fade start, the throttle passes through normally. Between fade start and
the ceiling, throttle reduces as pitch rises. Above the ceiling, the package
can request reverse motor current. The controller's `l_min_erpm` must be below
zero for this pull-down action. Start with a low Max pull-down current.

## IMU source

Select **Controller IMU**, **CU IMU** or **Auto**. Auto uses valid CU IMU
data first, then the controller IMU if it reports about 1 g.

Express data must be fresh and report both IMU OK and Zero Level complete.
The default timeout is 50 ms. Set mount axes and Zero Level on CU IMU;
the controller's IMU Status page shows the data received over CAN.

## Throttle and brake

Supported applications are ADC or ADC + UART, using **Current** or
**Current No Reverse Brake ADC2**. Other control types cannot arm.

The package uses the controller's ADC calibration, deadband and negative ramp
time. While assistance controls output, ADC2 braking is linear after the
deadband; custom brake expo is not applied. Disarmed riding uses the normal
ADC application.

ADC2 braking takes priority over throttle, pull-down, crash cutoff and IMU
loss. It uses non-reversing brake current within the configured brake limits.
Both controls must stay released for 0.3 seconds after braking before drive
can resume. Disarming does not skip that release check.

Changing to an unsupported application or control type cancels assistance and
waits for throttle release before returning control to that application.

## IMU loss and crash cutoff

If the IMU is lost or changes source while armed, output fades to zero. After
the throttle is released for 0.3 seconds, normal throttle returns even if the
IMU remains disconnected. Wheelie assistance needs valid, upright IMU data
for at least 0.2 seconds and released throttle before it can resume. Returning
sensor data while the throttle is held does not resume assistance.

Crash cutoff holds motor current at zero when pitch or roll exceeds its
configured limit for the cutoff delay. Defaults are 70° pitch, 60° roll and
250 ms. It also works while disarmed unless set to **Only when armed**.
Release the throttle and hold the bike upright for 0.5 seconds to clear it.
If IMU data is lost after cutoff, releasing the throttle for 0.3 seconds
restores normal throttle without wheelie assistance.

## Brake light

CU Wheelie sends brake-light commands to CU IMU during pull-down,
regen or deceleration. Defaults are 1.5 m/s² deceleration, 3 A regen, or
throttle released for 2 seconds while moving over 3 mph and slowing.
Change these on the Tune tab. The Live tab shows brake-light status and
deceleration; the light indicator is not a brake-lever reading.

## Screen setup

CUP-3.5 **Detection and Setup → VALUES** can save battery series, motor current
and battery current through direct controller Bluetooth or a compatible CAN
link. Setup requires Neutral, a stopped motor and the UART-only application.
Confirm the selected controller before saving.

Each saved field is read back and stored in package EEPROM. Motor tuning and
voltage cutoffs are unchanged. A lost setup connection keeps drive output held
until the connection returns and you tap **END**. This package also provides
its motor, Hall, ADC and IMU setup services; Motor Wizard belongs to CU Core ESC.

The [CAN display protocol](WHEELIE_CAN_PROTOCOL.md) documents status, settings
and arm/disarm messages. `(imu-diagnostics)` in the controller Lisp console
reports IMU faults, gaps and dropped or duplicate frames for support.

## Credits and license

Based on **Wheelie Assist 1.0.0 by [3ShulMotors](https://3shulmotors.com)**.
CU Wheelie adds CU IMU input, source selection, connection handling
and the Charged Up interface.

GPL-3.0. See `LICENSE.txt` for license and warranty terms.
