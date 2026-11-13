import QtQuick 2.15

Item {
    property string pkgName: "CU Dash"
    property string pkgDescriptionMd: "README-gen.md"
    property string pkgLisp: "main.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "cu_dash.vescpkg"

    // Returns true when this package is compatible with the connected device.
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // The CUP-3.5 runs VESC Express firmware, so it is a custom module
        if (hwType != "custom module") {
            return false
        }

        // This package needs the Charged Up display firmware: the 3.5" panel
        // driver, the touch controller and the Bluetooth central it talks to
        // controllers and batteries with. Only that firmware calls the board
        // CUP-3.5, so do not let it install anywhere else.
        return hwName == "cup-3.5"
    }
}
