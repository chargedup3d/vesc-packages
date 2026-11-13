import QtQuick 2.15

Item {
    property string pkgName: "CU Core ESC"
    property string pkgDescriptionMd: "README-gen.md"
    property string pkgLisp: "main.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "cu_esc_base.vescpkg"

    // This package uses the firmware 7 Lisp/native API. Cart telemetry
    // remains available on stock 6.00 without this package.
    function isCompatible (fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase();
        return hwType == "vesc" && fwRxParams.major == 7 && fwRxParams.minor == 0
    }
}
