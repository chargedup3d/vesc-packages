import QtQuick 2.15
Item {
    property string pkgName: "CU Express Link"
    property string pkgDescriptionMd: "README-gen.md"
    property string pkgLisp: "main.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "cu_link.vescpkg"
    function isCompatible(fwRxParams) {
        return fwRxParams.hwTypeStr().toLowerCase() === "custom module" &&
               fwRxParams.hw.toLowerCase() === "cu link";
    }
}
