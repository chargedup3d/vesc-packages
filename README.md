# Charged Up VESC Packages

Packages for Charged Up screens, links and motor controllers. Each package runs
on a specific device. Open its instructions below before installing.

Get the [CUP-3.5 screen from Charged Up 3D](https://chargedup3d.com/products/bike-e-scooter-advanced-display-3-5).

## Packages

| Package | Install on |
| --- | --- |
| [CU Express Core](cu_express_core/README.md) | Stock VESC Express T 7.00; CAN wired |
| [CU Core ESC](cu_esc_base/README.md) | VESC motor controller 7.00 |
| [CU Dash](cu_dash/README.md) | CUP-3.5 with compatible Charged Up native firmware and enlarged Lisp partition |
| [CU Wheelie](cu_wheelie/README.md) | VESC motor controller 7.00 plus supported controls and IMU |
| [CU IMU](cu_imu/README.md) | Express IMU hardware and Charged Up Express IMU firmware |
| [CU IO Link](cu_io/README.md) | CU IO Link hardware and matching Charged Up firmware |
| [CU Express Link](cu_link/README.md) | Express T already running Charged Up firmware named CU Link |

## Where to start

For an **Express T already wired to your bike**, install Express Core on the
Express T, then find it from your CUP-3.5 screen. Express Core uses stock VESC
Express 7.00 firmware and a CAN connection to the controller.

For **power modes and Motor Wizard**, install CU Core ESC on the motor controller.
The screen, Charged Up iOS app and VESC Tool package page use the same saved
power and speed limits.

For **CU Wheelie**, install it on the motor controller and install
CU IMU on the matching sensor board. CU Core ESC and CU Wheelie replace one
another. CU Wheelie does not include CU Core ESC's mode editor or Motor Wizard.

Dash updates a CUP-3.5 screen with Charged Up screen firmware and the enlarged
Lisp partition already installed. Express Link, IO Link and CU IMU require
their matching Charged Up firmware; use Express Core for a stock Express T.

CU Core ESC and CU Wheelie require controller firmware **7.00**. The screen can
read standard VESC data from a Flipsky 75100 on **6.00 or 7.00** without either
package. Setup and mode editing depend on the installed controller and link
versions.

## Install

1. Connect VESC Tool to the device you want to update. Check its hardware name
   and firmware version.
2. Back up its settings and existing package.
3. Open **VESC Packages** and install the matching `.vescpkg` file.
4. Power-cycle the device and follow that package's setup instructions.

## Build from source

You need Python 3.9+, Make and VESC Tool. CU Core ESC and CU Wheelie also need the
ARM GNU Embedded toolchain (`arm-none-eabi-gcc` and `arm-none-eabi-objcopy`)
on PATH. Each package folder contains its source, QML page, descriptor and
required libraries or assets.

```sh
make packages VESC_TOOL=/path/to/vesc_tool
```

This writes a `.vescpkg` into each package folder. To also build the package
archive, use Qt's `rcc`:

```sh
make VESC_TOOL=/path/to/vesc_tool RCC=/path/to/rcc
```

The archive is `vesc_pkg_all.rcc`. Run `make clean` to remove generated packages,
native helper binaries, generated QML/Lisp/descriptions and the archive.

Each package has its own `version` file, starting at `1.0`. Change that file
when releasing an update to that package. Package names stay the same.

Like Dash 35B, the build fills in `{{VERSION}}` in `ui.qml.in` and
`version.lisp.in`, then generates `ui.qml`, `version.lisp` and `README-gen.md`.
The package page shows the version; the description includes the build date
and Git commit when built from a checkout. Edit the `.in` files and `README.md`,
not their generated copies. Set `SOURCE_DATE_EPOCH` for a repeatable build date.

Device build IDs used by the app and flasher are separate from the package
release version.

Every package build recompiles its native C helpers in a temporary folder,
including after header, linker-script or compiler-option changes. A failed
compile stops packaging and leaves the previous package intact. Successful
builds update the helper binaries beside their sources. To use a toolchain
outside PATH, set `CROSS_COMPILE=/path/to/arm-none-eabi-` when running Make.

## Licenses and credits

Charged Up's original code and build tools use GPL-3.0-or-later. Existing
third-party notices are retained; see [NOTICE.txt](NOTICE.txt) and
[LICENSE.txt](LICENSE.txt). CU Wheelie is based on Wheelie Assist by
[3ShulMotors](https://3shulmotors.com). Dash's fonts keep their separate
licenses, listed in `cu_dash/FONT-NOTICES.txt`.

Full license texts and notices are also included in each built package's
description.
