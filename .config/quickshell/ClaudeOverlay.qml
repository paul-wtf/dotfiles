import Quickshell
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: overlay

    property bool claudeOpen:  false
    property real islandX:     0
    property real islandWidth: 200
    property var  limits:      []
    property var  stats:       null
    property int  fetchedAt:   0
    property bool stale:       false

    property string win:       "7d"
    property string hoverText: ""

    readonly property string nfFont: "JetBrainsMono Nerd Font"
    readonly property var    cur:    stats ? stats.windows[win] : null
    readonly property real   heatMax: {
        var m = 0
        if (stats) for (var d of stats.heatmap.cells) for (var v of d) m = Math.max(m, v)
        return m
    }

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
        if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "k"
        return String(n)
    }

    // Square root: linear lets one heavy hour wash out the rest, log flattens
    // hours spanning two orders of magnitude into one shade.
    function heat(v) {
        return v > 0 && heatMax > 0 ? Math.sqrt(v / heatMax) : 0
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
    implicitHeight: claudeOpen ? content.implicitHeight + 28 : 4
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
        width: Math.max(overlay.islandWidth, 560)

        radius: Theme.radius
        color:  Theme.zen ? "transparent" : Theme.panelBg
        border  { color: Theme.borderColor(0.55); width: Theme.overlayBorderWidth }
        clip:   true
        opacity: overlay.claudeOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        ColumnLayout {
            id: content
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14; topMargin: 13 }
            spacing: 10

            // ── Kopf + Zeitraum ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "󰚩"; color: Theme.clrPeach
                    font { family: overlay.nfFont; pixelSize: 13 } }
                Text { text: "Claude"; color: Theme.clrPeach
                    font { family: overlay.nfFont; pixelSize: 12; bold: true } }
                Text {
                    visible: overlay.stale && overlay.fetchedAt > 0
                    text: "  Stand " + Qt.formatTime(new Date(overlay.fetchedAt * 1000), "hh:mm")
                    color: Theme.clrSubtext0
                    font { family: overlay.nfFont; pixelSize: 11 }
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: ["5h", "24h", "7d"]
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool active: overlay.win === modelData
                        implicitWidth: winLabel.implicitWidth + 14
                        implicitHeight: 20
                        radius: 6
                        color: active ? Theme.clrSurface1 : "transparent"
                        border { color: Theme.clrSurface1; width: 1 }
                        Text {
                            id: winLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: active ? Theme.clrText : Theme.clrSubtext0
                            font { family: overlay.nfFont; pixelSize: 11; bold: active }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.win = modelData
                        }
                    }
                }
            }

            // ── Limits ───────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                opacity: overlay.stale ? 0.5 : 1.0

                Repeater {
                    model: overlay.limits
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

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
            }

            // ── Kacheln ──────────────────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 3; columnSpacing: 8; rowSpacing: 8

                Repeater {
                    model: {
                        var c = overlay.cur
                        if (!c) return []
                        return [
                            { label: "Sitzungen",   value: String(c.sessions) },
                            { label: "Prompts",     value: String(c.prompts) },
                            { label: "Tokens",      value: overlay.fmtTokens(c.tokens),
                              sub: "in/out " + overlay.fmtTokens(c.io) },
                            { label: "Aktive Tage", value: String(c.active_days) },
                            { label: "Spitze",      value: c.peak_hour === null ? "–" : c.peak_hour + " Uhr" },
                            { label: "Modell",      value: c.model || "–" },
                        ]
                    }
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 50
                        radius: 8
                        color: Theme.clrSurface0

                        Column {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
                            spacing: 2
                            Text {
                                text: modelData.label
                                color: Theme.clrSubtext0
                                font { family: overlay.nfFont; pixelSize: 10 }
                            }
                            Row {
                                spacing: 6
                                Text {
                                    text: modelData.value
                                    color: Theme.clrText
                                    font { family: overlay.nfFont; pixelSize: 15; bold: true }
                                }
                                Text {
                                    visible: !!modelData.sub
                                    text: modelData.sub || ""
                                    color: Theme.clrSubtext0
                                    font { family: overlay.nfFont; pixelSize: 10 }
                                    anchors.baseline: parent.children[0].baseline
                                }
                            }
                        }
                    }
                }
            }

            // ── Heatmap: 7 Tage × 24 Stunden ─────────────────────────────────
            Item {
                id: heatmap
                Layout.fillWidth: true
                readonly property int labelW: 24
                readonly property int gap:    3
                readonly property real cell:  (width - labelW - 23 * gap) / 24
                implicitHeight: 14 + 7 * (cell + gap)

                Repeater {
                    model: 8
                    delegate: Text {
                        required property int index
                        x: heatmap.labelW + index * 3 * (heatmap.cell + heatmap.gap)
                        text: index * 3
                        color: Theme.clrSubtext0
                        font { family: overlay.nfFont; pixelSize: 9 }
                    }
                }

                Repeater {
                    model: overlay.stats ? overlay.stats.heatmap.cells : []
                    delegate: Item {
                        id: dayRow
                        required property var modelData
                        required property int index
                        readonly property string day: overlay.stats.heatmap.days[index]
                        y: 14 + index * (heatmap.cell + heatmap.gap)
                        width: heatmap.width
                        height: heatmap.cell

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dayRow.day
                            color: Theme.clrSubtext0
                            font { family: overlay.nfFont; pixelSize: 10 }
                        }

                        Repeater {
                            model: dayRow.modelData
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                x: heatmap.labelW + index * (heatmap.cell + heatmap.gap)
                                width: heatmap.cell; height: heatmap.cell
                                radius: 3
                                color: Theme.clrSurface0

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: Theme.accent
                                    opacity: modelData > 0 ? 0.15 + 0.85 * overlay.heat(modelData) : 0
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: overlay.hoverText = dayRow.day + " " + index + " Uhr · "
                                        + overlay.fmtTokens(modelData) + " Tokens"
                                    onExited: overlay.hoverText = ""
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: overlay.hoverText || "Tokens pro Stunde · nur dieser Rechner"
                color: Theme.clrSubtext0
                font { family: overlay.nfFont; pixelSize: 10 }
            }
        }
    }
}
