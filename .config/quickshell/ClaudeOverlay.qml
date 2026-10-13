import Quickshell
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: overlay

    property bool claudeOpen:  false
    property real islandX:     0
    property real islandWidth: 200
    property var  limits:      []
    property var  tokens:      null
    property int  fetchedAt:   0
    property bool stale:       false

    readonly property string nfFont: "JetBrainsMono Nerd Font"

    property real nowSec: Date.now() / 1000
    Timer {
        interval: 30000; repeat: true; running: overlay.claudeOpen; triggeredOnStart: true
        onTriggered: overlay.nowSec = Date.now() / 1000
    }

    function severityColor(s) {
        if (s === "normal")  return Theme.clrGreen
        if (s === "warning") return Theme.clrYellow
        return Theme.clrRed
    }

    function countdown(resetsAt) {
        var s = Math.max(0, resetsAt - overlay.nowSec)
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
        return m + "m"
    }

    function fmtTokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "G"
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "k"
        return String(n)
    }

    // ── Fenster ──────────────────────────────────────────────────────────────
    screen: {
        for (var i = 0; i < Quickshell.screens.length; i++)
            if (Quickshell.screens[i].name === "HDMI-A-1")
                return Quickshell.screens[i]
        return Quickshell.screens[0]
    }

    anchors { top: true; left: true; right: true }
    margins { top: Theme.overlayTop; left: 12; right: 12 }
    exclusiveZone: -1
    color: "transparent"
    implicitHeight: claudeOpen ? content.implicitHeight + 26 : 4
    Behavior on implicitHeight { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }

    ZenPanelSurface {
        targetX:     panel.x
        targetWidth: panel.width
        panelHeight: panel.height
        open:        overlay.claudeOpen
    }

    Rectangle {
        id: panel

        x: Math.max(0, Math.min(
               overlay.islandX + (overlay.islandWidth - width) / 2,
               parent.width - width))
        anchors { top: parent.top; bottom: parent.bottom }
        width: Math.max(overlay.islandWidth, 340)

        radius: Theme.radius
        color:  Theme.zen ? "transparent" : Theme.panelBg
        border  { color: Theme.borderColor(0.55); width: Theme.overlayBorderWidth }
        clip:   true
        opacity: overlay.claudeOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        ColumnLayout {
            id: content
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14; topMargin: 13 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "󰚩"; color: Theme.clrPeach
                    font { family: overlay.nfFont; pixelSize: 13 } }
                Text { text: "Claude"; color: Theme.clrPeach
                    font { family: overlay.nfFont; pixelSize: 12; bold: true } }
                Item { Layout.fillWidth: true }
                Text {
                    visible: overlay.stale && overlay.fetchedAt > 0
                    text: "Stand " + Qt.formatTime(new Date(overlay.fetchedAt * 1000), "hh:mm")
                    color: Theme.clrSubtext0
                    font { family: overlay.nfFont; pixelSize: 11 }
                }
            }

            // ── Limits ───────────────────────────────────────────────────────
            Repeater {
                model: overlay.limits
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    opacity: overlay.stale ? 0.5 : 1.0

                    Text {
                        text: modelData.label
                        color: Theme.clrSubtext1
                        font { family: overlay.nfFont; pixelSize: 11 }
                        Layout.preferredWidth: 92
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6; radius: 3
                        color: Theme.clrSurface0
                        Rectangle {
                            width: parent.width * Math.min(1, modelData.percent / 100)
                            height: parent.height; radius: 3
                            color: overlay.severityColor(modelData.severity)
                        }
                    }
                    Text {
                        text: Math.round(modelData.percent) + "%"
                        color: Theme.clrText
                        horizontalAlignment: Text.AlignRight
                        font { family: overlay.nfFont; pixelSize: 11 }
                        Layout.preferredWidth: 34
                    }
                    Text {
                        text: modelData.resets_at > 0 ? overlay.countdown(modelData.resets_at) : ""
                        color: Theme.clrSubtext0
                        horizontalAlignment: Text.AlignRight
                        font { family: overlay.nfFont; pixelSize: 11 }
                        Layout.preferredWidth: 52
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.clrSurface1 }

            // ── Tokens (nur dieser Rechner) ──────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 4; columnSpacing: 10; rowSpacing: 3

                Repeater {
                    model: {
                        var cells = ["Tokens", "5h", "24h", "7d"]
                        var rows = [["in/out", "io"], ["Cache", "cache"]]
                        for (var r = 0; r < rows.length; r++) {
                            cells.push(rows[r][0])
                            for (var w of ["5h", "24h", "7d"])
                                cells.push(overlay.tokens ? overlay.fmtTokens(overlay.tokens[w][rows[r][1]]) : "…")
                        }
                        return cells
                    }
                    delegate: Text {
                        required property var modelData
                        required property int index
                        readonly property bool rowLabel: index % 4 === 0
                        text: modelData
                        color: index < 4 ? Theme.clrSubtext0 : rowLabel ? Theme.clrSubtext1 : Theme.clrText
                        horizontalAlignment: rowLabel ? Text.AlignLeft : Text.AlignRight
                        font { family: overlay.nfFont; pixelSize: 11; bold: index === 0 }
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
