import QtQuick 2.15

Item {
    property string pkgName: "CU IO Link"
    property string pkgDescriptionMd: "README-gen.md"
    property string pkgLisp: "main.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "cu_io.vescpkg"

    // Returns true when this package is compatible with the connected device.
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        if (hwType != "custom module") {
            return false
        }

        // Needs the CU IO Link firmware: it frees the hat's switch
        // and AUX pins, and reports the board as CU IO Link.
        return hwName == "cu io link"
    }
}
