# CU IO Link

Connects a CUP-3.5 screen to the motor controller's CAN bus and adds tail/AUX
lights, two switch inputs and an optional ANT BMS connection.

Install on a board running CU IO Link firmware. Its hardware name in
VESC Tool must be **CU IO Link**.

## Install and connect

1. Connect the IO Link to the controller's CAN bus and power it up.
2. Connect VESC Tool to the IO Link and back up its package and settings.
3. Install `cu_io.vescpkg` through **VESC Packages**, then power-cycle.
4. Power up the CUP-3.5 and pair it with the link.
5. Open the package page to configure lights and switches. Press **SAVE** to
   keep changes.

## Lights and switches

**TAIL** provides a running light, brake light and turn signals. **AUX** can
copy the tail light, act as a headlight or show one turn signal.

**SW1** and **SW2** each support a button with short/long presses or an on/off
switch. Assign signals, hazards, lights, drive modes, Neutral, reverse, cruise
or other available actions. The two inputs can also form a three-position
speed switch.

Local switch actions work without a screen. Actions that change the display
need the paired screen connected.

## Controller and battery data

The link discovers the controller and sends its telemetry to the paired
screen. Mode selection, kids limits and Wheelie commands depend on the
controller package. Setup and mode editing also depend on the link version.

Select a compatible ANT BMS on the package page to read its data over Bluetooth.

See `LICENSE` for the original notice, `LICENSE.txt` for the full GPLv3 terms
and `NOTICE.txt` for credits.

## Build from source

Requires Python 3.9+, Make and VESC Tool.
Build from the root of the full repository so the shared `tools/` folder is
included:

```sh
make -C cu_io VESC_TOOL=/path/to/vesc_tool
```

Output: `cu_io/cu_io.vescpkg`. See the
[build options](https://github.com/chargedup3d/vesc-packages#build-from-source)
for tool paths, versioning and archive builds.
