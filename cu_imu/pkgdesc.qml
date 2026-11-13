import QtQuick 2.15

Item {
    property string pkgName: "CU IMU"
    property string pkgDescriptionMd: "README-gen.md"
    property string pkgLisp: "imu.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "cu_imu.vescpkg"

    // Only for the Express Open board running Express IMU firmware
    // (on-board LSM6DS3TR-C, tail light on GPIO5)
    function isCompatible (fwRxParams) {
        return fwRxParams.hw === "Express IMU";
    }
}
