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

    // Passed in from the device list. Matching is done by IP, not by name,
    // because the list's name column can differ from the JSON HostName
    // (especially for Android nodes).
    property string hostname: ""
    property string nodeIp: ""
    property bool isSelf: false

    // Node data (populated by loadNode()). Plain string/bool properties:
    // every row below is a fixed item bound to them. Deliberately NO
    // Repeater/JS-array model: on SFOS 5.2 (Qt 5.6) a Repeater with a JS
    // array model reports the right count but never instantiates delegate
    // items, which left the rows blank on the phone.
    property bool hasData: false
    property string dnsName: ""
    property string ip4: ""
    property string ip6: ""
    property string osName: ""
    property string keyExpiry: ""
    property bool online: false

    // Ping state
    readonly property int pingCount: 10
    property bool pinging: false
    property var graphData: []      // [ms, ms, ...] appended per sample
    property int sampleCount: 0
    property double latestMs: 0
    property bool lastRelayed: false
    property bool hasResult: false

    PageHeader {
        id: pageHeader
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

    Connections {
        target: client

        onPingSample: {
            page.graphData = page.graphData.concat([latencyMs]);
            page.sampleCount += 1;
            page.latestMs = latencyMs;
            page.lastRelayed = relayed;
            page.hasResult = true;
        }

        onPingFinished: {
            page.pinging = false;
        }
    }

    function loadNode() {
        try {
            var status = JSON.parse(client.getStatusJson());
            var node = null;
            var peers = status.Peer || {};

            for (var id in peers) {
                var ips = peers[id].TailscaleIPs || [];
                if (ips.indexOf(page.nodeIp) !== -1) {
                    node = peers[id];
                    break;
                }
            }

            if (!node && status.Self) {
                var selfIps = status.Self.TailscaleIPs || [];
                if (selfIps.indexOf(page.nodeIp) !== -1 || page.isSelf)
                    node = status.Self;
            }

            if (!node) {
                console.log("DevicePage: no node found for " + page.nodeIp);
                return;
            }

            page.dnsName = node.DNSName ? node.DNSName.replace(/\.$/, "") : "";

            var ips2 = node.TailscaleIPs || [];
            page.ip4 = "";
            page.ip6 = "";
            for (var i = 0; i < ips2.length; i++) {
                if (ips2[i].indexOf(":") !== -1)
                    page.ip6 = ips2[i];
                else if (page.ip4 === "")
                    page.ip4 = ips2[i];
            }
            page.osName = node.OS || "";

            page.keyExpiry = node.KeyExpiry
                ? Qt.formatDateTime(new Date(node.KeyExpiry), Qt.TextDate)
                : qsTr("No expiry");

            page.online = node.Online === true;
            page.hasData = true;
        } catch (error) {
            console.log("DevicePage: loadNode failed: " + error);
        }
    }

    function startPing() {
        if (page.pinging)
            return;
        page.graphData = [];
        page.sampleCount = 0;
        page.latestMs = 0;
        page.hasResult = false;
        page.pinging = true;
        client.startPing(page.nodeIp, page.pingCount);
    }

    ViewPlaceholder {
        anchors.centerIn: parent
        visible: !page.hasData
        text: qsTr("No data available")
    }

    SilicaFlickable {
        anchors.fill: parent
        visible: page.hasData
        contentHeight: contentColumn.implicitHeight
                        + Theme.pageHeaderHeight
                        + Theme.paddingLarge * 2

        Column {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                topMargin: Theme.pageHeaderHeight + Theme.paddingLarge
                leftMargin: Theme.horizontalPageMargin
                rightMargin: Theme.horizontalPageMargin
            }
            spacing: Theme.paddingLarge

            Label {
                text: qsTr("Tailscale addresses")
                font.pixelSize: Theme.fontSizeSmall
                font.letterSpacing: 0.5
                color: Theme.secondaryColor
            }

            // MagicDNS ----------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.dnsName !== ""

                Label {
                    width: contentColumn.width
                    text: page.dnsName
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                }
                Label {
                    text: qsTr("MagicDNS")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // IPv4 ---------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.ip4 !== ""

                Label {
                    width: contentColumn.width
                    text: page.ip4
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                }
                Label {
                    text: qsTr("IPv4")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // IPv6 ---------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.ip6 !== ""

                Label {
                    width: contentColumn.width
                    text: page.ip6
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                }
                Label {
                    text: qsTr("IPv6")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // OS -----------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.osName !== ""

                Label {
                    width: contentColumn.width
                    text: page.osName
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: Theme.primaryColor
                }
                Label {
                    text: qsTr("OS")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // Key expiry ---------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.hasData

                Label {
                    width: contentColumn.width
                    text: page.keyExpiry
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    color: page.keyExpiry !== qsTr("No expiry")
                        ? Theme.primaryColor : Theme.secondaryColor
                }
                Label {
                    text: qsTr("Key expiry")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // Status -------------------------------------------------------
            Column {
                width: contentColumn.width
                spacing: Theme.paddingSmall / 2
                visible: page.hasData

                Label {
                    width: contentColumn.width
                    text: page.online ? qsTr("Online") : qsTr("Offline")
                    font.pixelSize: Theme.fontSizeMedium
                    color: page.online ? Theme.highlightColor : Theme.errorColor
                }
                Label {
                    text: qsTr("Status")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }

            // Ping section ------------------------------------------------
            Rectangle {
                width: contentColumn.width
                height: 1
                color: Theme.rgba(Theme.primaryColor, 0.12)
            }

            Label {
                text: qsTr("Ping")
                font.pixelSize: Theme.fontSizeSmall
                font.letterSpacing: 0.5
                color: Theme.secondaryColor
            }

            Label {
                width: contentColumn.width
                visible: page.isSelf
                text: qsTr("This is your own device — Tailscale can't ping itself.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.secondaryColor
            }

            Row {
                id: pingRow
                visible: !page.isSelf
                width: contentColumn.width
                spacing: Theme.paddingMedium

                Button {
                    id: pingButton
                    width: parent.width * 0.5
                    text: page.pinging ? qsTr("Stop") : qsTr("Ping")
                    onClicked: {
                        if (page.pinging)
                            client.cancelPing();
                        else
                            page.startPing();
                    }
                }

                Label {
                    id: pingLatest
                    anchors.verticalCenter: pingButton.verticalCenter
                    visible: page.hasResult
                    width: parent.width - pingButton.width - parent.spacing
                    text: page.latestMs + " ms"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignRight
                    color: Theme.primaryColor
                }
            }

            Label {
                id: connLabel
                width: contentColumn.width
                visible: page.hasResult
                text: page.lastRelayed ? qsTr("Relayed connection (via DERP)")
                                      : qsTr("Direct connection")
                font.pixelSize: Theme.fontSizeSmall
                color: page.lastRelayed ? Theme.secondaryHighlightColor : Theme.highlightColor
            }

            // Latency graph: fixed bars (one per ping slot). No Canvas —
            // pure Rectangles, the same primitives that render everywhere
            // else on this page.
            Item {
                id: graphBox
                width: contentColumn.width
                height: 190
                visible: page.sampleCount > 0

                function barMax() {
                    var m = 0;
                    for (var i = 0; i < page.graphData.length; i++)
                        if (page.graphData[i] > m)
                            m = page.graphData[i];
                    return Math.max(10, Math.ceil(m));
                }

                function barHeight(v) {
                    return Math.max(4, (v / graphBox.barMax()) * (plotArea.height - 8));
                }

                Label {
                    id: maxLabel
                    anchors {
                        top: parent.top
                        left: parent.left
                    }
                    text: graphBox.barMax() + " ms"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }

                Rectangle {
                    id: plotArea
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        top: parent.top
                        topMargin: maxLabel.height + 6
                    }
                    color: "transparent"

                    Rectangle {
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 1
                        color: Theme.rgba(Theme.primaryColor, 0.12)
                    }
                    Rectangle {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right }
                        height: 1
                        color: Theme.rgba(Theme.primaryColor, 0.12)
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 1
                        color: Theme.rgba(Theme.primaryColor, 0.25)
                    }

                    Row {
                        id: barRow
                        anchors {
                            left: parent.left
                            bottom: parent.bottom
                        }
                        width: parent.width
                        spacing: 8

                        // slot 0
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 0 < page.sampleCount ? graphBox.barHeight(page.graphData[0]) : 2
                            visible: 0 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 1 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 1
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 1 < page.sampleCount ? graphBox.barHeight(page.graphData[1]) : 2
                            visible: 1 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 2 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 2
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 2 < page.sampleCount ? graphBox.barHeight(page.graphData[2]) : 2
                            visible: 2 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 3 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 3
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 3 < page.sampleCount ? graphBox.barHeight(page.graphData[3]) : 2
                            visible: 3 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 4 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 4
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 4 < page.sampleCount ? graphBox.barHeight(page.graphData[4]) : 2
                            visible: 4 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 5 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 5
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 5 < page.sampleCount ? graphBox.barHeight(page.graphData[5]) : 2
                            visible: 5 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 6 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 6
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 6 < page.sampleCount ? graphBox.barHeight(page.graphData[6]) : 2
                            visible: 6 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 7 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 7
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 7 < page.sampleCount ? graphBox.barHeight(page.graphData[7]) : 2
                            visible: 7 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 8 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 8
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 8 < page.sampleCount ? graphBox.barHeight(page.graphData[8]) : 2
                            visible: 8 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 9 ? Theme.primaryColor : Theme.highlightColor
                        }
                        // slot 9
                        Rectangle {
                            width: (barRow.width - 9 * barRow.spacing) / 10
                            height: 9 < page.sampleCount ? graphBox.barHeight(page.graphData[9]) : 2
                            visible: 9 < page.sampleCount
                            radius: 3
                            color: page.sampleCount === 10 ? Theme.primaryColor : Theme.highlightColor
                        }
                    }
                }
            }

            Label {
                width: contentColumn.width
                visible: page.hasResult
                text: page.sampleCount + "/" + page.pingCount + " " + qsTr("pings")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: loadNode()
}
