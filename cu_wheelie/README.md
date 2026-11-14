# CU Wheelie

Wheelie assistance for a VESC motor controller. Uses pitch and pitch rate to
reduce throttle as the front rises and apply pull-down current above the
configured ceiling.

Requires **VESC firmware 7.00**, a working IMU and supported ADC throttle/brake
controls. It replaces CU Core ESC on the controller and includes its Power
Modes, Motor Wizard and calibration services.

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

## Power modes

The **Power Modes** tab, CUP-3.5 screen and Charged Up iOS app edit the same
saved power and speed limits. Disarm Wheelie, select **N**, stop the motor and
end any setup session before saving. The editor reads the limits back before
confirming a save.

| Mode | Default power | Default speed limit |
| --- | --- | --- |
| Reverse | 50% | 15 km/h |
| 1 | 50% | 20 km/h |
| 2 | 60% | 25 km/h |
| 3 | 100% | 250 km/h |

CU Wheelie starts in **Mode 3 with assistance disarmed**, so a 3Shul display
can still arm it without sending a separate mode command. Mode 3's high default
leaves the controller's original speed limit in effect. Set limits for your
vehicle before riding.

Drive and brake percentages limit the controller's configured current scales;
they cannot raise its underlying limits. Speed is stored in km/h. Wheelie
assistance uses the selected mode's limits, including its brake-current scale
for pull-down while moving forward. Kids caps can reduce power and speed
further. The last applied limits remain if the screen disconnects.

Neutral disarms assistance, blocks drive and retains braking. Reverse requires
assistance disarmed, a stopped motor and released controls. Cruise is disabled
while CU Wheelie is installed.

Mode limits are temporary motor settings. Before editing or backing up the
underlying motor configuration in VESC Tool, remove CU Wheelie, restart and
read the settings again. Reinstall and power-cycle afterward. Use the mode
editor for ordinary power and speed changes.

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

## Motor Wizard and screen setup

Use CUP-3.5 **Detection and Setup** through direct controller Bluetooth or a
compatible Charged Up CAN link. Disarm Wheelie, select Neutral and stop the
motor before starting. Setup holds drive output until **END**.

Motor Wizard uses VESC Tool's motor-size presets and native measurements.
Detection can rotate the motor. Secure it and keep clear before starting.
A successful detection saves the tune after checking and reading it back.
It preserves application settings, battery limits, speed settings and switching
frequency. It may lower motor current to the preset's limit, but cannot raise
the existing caps. Encoder setups are rejected; failed Hall detection does not
replace an existing Hall tune with sensorless operation.

**STOP** or a lost setup connection cancels detection and restores the previous
configuration. Wait for **END** while measurements stop. If restoration fails,
output stays held and **END** retries it.

Motor previews and Hall checks do not save a tune. Throttle/brake calibration
saves verified endpoints without enabling ADC control. **VALUES** saves battery
series, motor current and battery current with readback; it leaves voltage
cutoffs unchanged. VALUES requires the UART-only application. Confirm the
selected controller before saving.

The [CAN display protocol](WHEELIE_CAN_PROTOCOL.md) documents status, settings
and arm/disarm messages. `(imu-diagnostics)` in the controller Lisp console
reports IMU faults, gaps and dropped or duplicate frames for support.

## Build from source

Requires Python 3.9+, Make and VESC Tool. Also install `arm-none-eabi-gcc`
and `arm-none-eabi-objcopy` for the native helpers.
Build from the root of the full repository so the shared `tools/` folder is
included:

```sh
make -C cu_wheelie VESC_TOOL=/path/to/vesc_tool
```

Output: `cu_wheelie/cu_wheelie.vescpkg`. See the
[build options](https://github.com/chargedup3d/vesc-packages#build-from-source)
for tool paths, versioning and archive builds.

## Credits and license

Based on **Wheelie Assist 1.0.0 by [3ShulMotors](https://3shulmotors.com)**.
CU Wheelie adds CU IMU input, source selection, connection handling, shared
power modes, setup services and the Charged Up interface. Motor Wizard presets
follow [VESC Tool](https://github.com/vedderb/vesc_tool/blob/53dd253c9e3b60a38584d776d4dadcc14b51b0a4/mobile/SetupWizardFoc.qml).

GPL-3.0. See `LICENSE.txt` for license and warranty terms.
