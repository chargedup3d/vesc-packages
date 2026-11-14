# CU IMU

Pitch and roll sensor, screen link and tail-light controller for the Charged Up
Express IMU board. CU IMU sends pitch, roll and pitch rate over CAN.
CU Wheelie uses these readings on the motor controller.

The board must run Charged Up Express IMU firmware and report **Express IMU**
in VESC Tool. This package uses its onboard LSM6DS3TR-C sensor.

## Install and set up

1. Mount the board rigidly to the bike frame. Keep it off the handlebars and
   avoid foam mounting.
2. Connect it to the controller's CAN bus. The CAN connector must supply 5 V;
   powering the pogo pads alone leaves CAN off.
3. Back up its package and settings, then install `cu_imu.vescpkg` through
   **VESC Packages** and power-cycle.
4. Stop and disarm CU Wheelie. Connect VESC Tool directly to the sensor board
   over Bluetooth and open **APPUI → Setup** in CU IMU.
5. Select the forward and up sensor axes, then press **Save mount**.
6. Hold the bike level and still, then select **Zero Level**.

With Wheelie disarmed and both controls released, check the readings: lifting
the front should give positive pitch and pitch rate; holding it still should
bring the rate near zero; lowering it should give negative pitch rate. Leaning
right should give positive roll.

Zero Level corrects angle offsets, not the gyro axes. Set the mount axes first
and repeat Zero Level after changing them.

Setup needs current controller data showing the bike stopped and Wheelie
disarmed. If that data is missing, setup stays disabled. Zero Level cancels if
the controller moves, arms or stops reporting its status.

## Screen connection

CU IMU also links the controller to a CUP-3.5 over ESP-NOW. It remembers
the paired screen and carries controller telemetry, drive-mode commands and
Wheelie status. The controller's **IMU Status** page shows the sensor data it
receives; mount and Zero Level settings are on CU IMU's Setup page.

## Tail light

Set the LED type, count and brightness on the package page. The default is
15 SK6812 GRBW LEDs. The strip shares the controller's 5 V supply.

| State | Light |
| --- | --- |
| Normal | Dim red running light, or party mode |
| Braking | Solid red |
| Turn signal or hazards | Signal or hazard pattern |
| Crash cutoff or IMU lost | Flashing amber |
| Controller connection lost | Running light only |

Brake and hazard signals override party mode.

## Diagnostics

The controller's IMU Status page shows received angles and sensor health.
CAN traffic and processing load affect update rate and sample age.

For support, `(imu-diagnostics)` in the Express Lisp console reports sample
rate, sample age, I2C errors and gaps. The same command on the Wheelie
controller reports IMU faults, receive gaps and dropped or duplicate frames.
Counters reset when the package restarts.

## Build from source

Requires Python 3.9+, Make and VESC Tool.
Build from the root of the full repository so the shared `tools/` folder is
included:

```sh
make -C cu_imu VESC_TOOL=/path/to/vesc_tool
```

Output: `cu_imu/cu_imu.vescpkg`. See the
[build options](https://github.com/chargedup3d/vesc-packages#build-from-source)
for tool paths, versioning and archive builds.

## License

GPL-3.0-or-later. See `LICENSE.txt` and `NOTICE.txt` for terms and credits.
