/*
    Copyright (C) 2022-2026 Andrea Scarpino <andrea@scarpino.dev>
    All rights reserved.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property string hostname: ""
    property string nodeIp: ""

    property bool hasData: false
    property string dnsName: ""
    property string ipV4: ""
    property string ipV6: ""
    property string keyExpiry: ""
    property bool online: false

    property bool pingTried: false
    property string pingResult: ""

    function loadNode() {
        try {
            var status = JSON.parse(client.getStatusJson());
            var node = null;

            var peers = status.Peer || {};
            for (var id in peers) {
                if (peers[id].HostName === page.hostname) {
                    node = peers[id];
                    break;
                }
            }
            // the local node is reported in Self, not in Peer
            if (!node && status.Self && status.Self.HostName === page.hostname)
                node = status.Self;
            if (!node)
                return;

            page.dnsName = node.DNSName ? node.DNSName.replace(/\.$/, "") : "";
            page.online = node.Online;

            var ips = node.TailscaleIPs || [];
            for (var i = 0; i < ips.length; i++) {
                if (ips[i].indexOf(":") !== -1)
                    page.ipV6 = ips[i];
                else if (page.ipV4 === "")
                    page.ipV4 = ips[i];
            }

            if (node.KeyExpiry)
                page.keyExpiry = Qt.formatDateTime(new Date(node.KeyExpiry), Qt.TextDate);

            page.hasData = true;
        } catch (error) {
            console.log("Failed to load node status:", error);
        }
    }

    header: PageHeader {
        title: page.hostname

        IconButton {
            id: backButton
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            icon.source: "image://theme/icon-m-back"

            onClicked: pageStack.pop()
        }
    }

    ViewPlaceholder {
        anchors.centerIn: parent
        visible: !page.hasData
        text: qsTr("No data available")
    }

    SilicaFlickable {
        anchors.fill: parent
        visible: page.hasData
        contentHeight: contentColumn.implicitHeight + Theme.paddingLarge * 2

        Column {
            id: contentColumn
            width: parent.width
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                topMargin: Theme.paddingLarge
            }
            spacing: Theme.paddingLarge

            Row {
                width: parent.width
                spacing: Theme.paddingSmall

                Label {
                    id: dnsNameLabel
                    text: qsTr("MagicDNS name")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.secondaryColor
                }

                Label {
                    width: parent.width - dnsNameLabel.width - parent.spacing
                    text: page.dnsName
                    font.pixelSize: Theme.fontSizeMedium
                    truncationMode: TruncationMode.Fade
                }
            }

            Row {
                width: parent.width
                spacing: Theme.paddingSmall

                Label {
                    id: ipV4Label
                    text: qsTr("IPv4")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.secondaryColor
                }

                Label {
                    width: parent.width - ipV4Label.width - parent.spacing
                    text: page.ipV4
                    font.pixelSize: Theme.fontSizeMedium
                    truncationMode: TruncationMode.Fade
                }
            }

            Row {
                width: parent.width
                spacing: Theme.paddingSmall

                Label {
                    id: ipV6Label
                    text: qsTr("IPv6")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.secondaryColor
                }

                Label {
                    width: parent.width - ipV6Label.width - parent.spacing
                    text: page.ipV6
                    font.pixelSize: Theme.fontSizeMedium
                    truncationMode: TruncationMode.Fade
                }
            }

            Row {
                width: parent.width
                spacing: Theme.paddingSmall

                Label {
                    id: keyExpiryLabel
                    text: qsTr("Key expiry")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.secondaryColor
                }

                Label {
                    width: parent.width - keyExpiryLabel.width - parent.spacing
                    text: page.keyExpiry !== "" ? page.keyExpiry : qsTr("No expiry")
                    font.pixelSize: Theme.fontSizeMedium
                    truncationMode: TruncationMode.Fade
                }
            }

            Row {
                width: parent.width
                spacing: Theme.paddingSmall

                Label {
                    id: statusLabel
                    text: qsTr("Status")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.secondaryColor
                }

                Label {
                    width: parent.width - statusLabel.width - parent.spacing
                    text: page.online ? qsTr("Online") : qsTr("Offline")
                    font.pixelSize: Theme.fontSizeMedium
                    color: page.online ? Theme.highlightColor : Theme.secondaryColor
                }
            }

            Button {
                id: pingButton
                width: parent.width
                text: qsTr("Ping")
                enabled: page.ipV4 !== "" || page.ipV6 !== ""

                onClicked: {
                    page.pingTried = true;
                    page.pingResult = "";
                    page.pingResult = client.ping(page.ipV4 !== "" ? page.ipV4 : page.ipV6);
                }
            }

            Label {
                visible: page.pingTried
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.pingResult !== "" ? page.pingResult : qsTr("Unreachable")
                font.pixelSize: Theme.fontSizeMedium
                color: page.pingResult !== "" ? Theme.primaryColor : Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: loadNode()
}
