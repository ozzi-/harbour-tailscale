import QtQuick 2.0
import Sailfish.Silica 1.0
import "." as Pages
Item {
    width: 360
    height: 720

    Pages.DevicePage {
        id: dp
        width: 360
        height: 720
        hostname: "laptop"
        nodeIp: "100.64.0.1"
        isSelf: true
    }
}
