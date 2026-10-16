import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: overlay

    property bool musicOpen:     false
    property real islandX:       0
    property real islandWidth:   200
    property var  player:        null
    property real trackPosition: 0
    property real trackLength:   0

    readonly property string nfFont: "JetBrainsMono Nerd Font"
    readonly property bool showLyrics: TidalLyrics.synced && TidalLyrics.isTidal(player)
    readonly property int  lyricsHeight: 120

    function fmt(s) {
        if (!s || s <= 0) return "0:00"
        s = Math.floor(s)
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
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
    // The click-outside catcher maps on open, so on the same layer it would
    // stack above this window and swallow clicks on the controls.
    WlrLayershell.layer: WlrLayer.Overlay
    implicitHeight: musicOpen ? (showLyrics ? 175 + lyricsHeight + 21 : 175) : 4
    Behavior on implicitHeight { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }

    // Zen: Mantle-Fläche, die nahtlos aus der Bar wächst (Flares + Jelly)
    ZenPanelSurface {
        targetX:     panel.x
        targetWidth: panel.width
        panelHeight: panel.height
        open:        overlay.musicOpen
    }

    // ── Panel (unter Music Island zentriert) ─────────────────────────────────
    Rectangle {
        id: panel

        // Unter der Music Island ausrichten, an Kanten clampen
        x: Math.max(0, Math.min(
               overlay.islandX + (overlay.islandWidth - width) / 2,
               parent.width - width))
        anchors { top: parent.top; bottom: parent.bottom }
        width: Math.max(overlay.islandWidth, 290)

        radius: Theme.radius
        color:  Theme.zen ? "transparent" : Theme.panelBg
        border  { color: Theme.borderColor(0.55); width: Theme.overlayBorderWidth }
        clip:   true
        opacity: overlay.musicOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        ColumnLayout {
            anchors { fill: parent; margins: 14; topMargin: 13; bottomMargin: 13 }
            spacing: 10

            // ── Album Art + Track Info ────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 13

                // Album Art
                Rectangle {
                    width: 66; height: 66
                    radius: 8
                    color: Theme.clrSurface0
                    clip: true

                    Image {
                        id: albumArt
                        anchors.fill: parent
                        source: overlay.player ? (overlay.player.trackArtUrl ?? "") : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰝚"
                        color: Theme.clrMauve
                        font { family: overlay.nfFont; pixelSize: 26 }
                        visible: albumArt.status !== Image.Ready
                    }
                }

                // Track-Infos
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3
                    clip: true

                    Text {
                        Layout.fillWidth: true
                        text: overlay.player ? (overlay.player.trackTitle ?? "–") : "–"
                        color: Theme.clrText
                        font { family: overlay.nfFont; pixelSize: 13; bold: true }
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: overlay.player ? (overlay.player.trackArtist ?? "") : ""
                        color: Theme.clrSubtext0
                        font { family: overlay.nfFont; pixelSize: 12 }
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                    Text {
                        Layout.fillWidth: true
                        text: overlay.player ? (overlay.player.trackAlbum ?? "") : ""
                        color: Qt.rgba(Theme.clrSubtext0.r, Theme.clrSubtext0.g,
                                       Theme.clrSubtext0.b, 0.5)
                        font { family: overlay.nfFont; pixelSize: 11 }
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }

                    // Player-Badge
                    Rectangle {
                        visible: overlay.player !== null
                        height: 17
                        width: badgeText.implicitWidth + 12
                        radius: 4
                        color: Qt.rgba(Theme.clrSky.r, Theme.clrSky.g, Theme.clrSky.b, 0.10)
                        border { color: Theme.borderColor(0.25); width: 1 }
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: overlay.player ? (overlay.player.identity ?? "") : ""
                            color: Qt.rgba(Theme.clrSky.r, Theme.clrSky.g, Theme.clrSky.b, 0.65)
                            font { family: overlay.nfFont; pixelSize: 10 }
                        }
                    }
                }
            }

            // ── Trennlinie ───────────────────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.clrSurface1; opacity: 0.45 }

            // ── Steuerung ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Item { Layout.fillWidth: true }

                Text {
                    text: "󰒮"
                    color: Theme.clrSubtext0
                    font { family: overlay.nfFont; pixelSize: 19 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (overlay.player) overlay.player.previous() }
                    }
                }

                Item { width: 22 }

                Text {
                    text: (overlay.player &&
                           overlay.player.playbackState === MprisPlaybackState.Playing)
                          ? "󰏥" : "󰐊"
                    color: Theme.clrSky
                    font { family: overlay.nfFont; pixelSize: 28 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!overlay.player) return
                            if (overlay.player.playbackState === MprisPlaybackState.Playing)
                                overlay.player.pause()
                            else
                                overlay.player.play()
                        }
                    }
                }

                Item { width: 22 }

                Text {
                    text: "󰒭"
                    color: Theme.clrSubtext0
                    font { family: overlay.nfFont; pixelSize: 19 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (overlay.player) overlay.player.next() }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // ── Fortschrittsbalken ───────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: overlay.fmt(overlay.trackPosition)
                    color: Theme.clrSubtext0
                    font { family: overlay.nfFont; pixelSize: 11 }
                }

                Item {
                    Layout.fillWidth: true
                    height: 5
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent; radius: 3
                        color: Theme.clrSurface1
                    }
                    Rectangle {
                        width: overlay.trackLength > 0
                               ? parent.width * Math.min(overlay.trackPosition / overlay.trackLength, 1)
                               : 0
                        height: parent.height; radius: 3
                        color: Theme.clrSky
                    }
                    MouseArea {
                        anchors { fill: parent; margins: -8 }
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (overlay.player && overlay.trackLength > 0) {
                                var pos = Math.max(0, Math.min(mouse.x / width, 1)) * overlay.trackLength
                                overlay.player.position = pos
                            }
                        }
                    }
                }

                Text {
                    text: overlay.fmt(overlay.trackLength)
                    color: Theme.clrSubtext0
                    font { family: overlay.nfFont; pixelSize: 11 }
                }
            }

            // ── Lyrics ───────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1; color: Theme.clrSurface1; opacity: 0.45
                visible: overlay.showLyrics
            }

            ListView {
                id: lyricsList
                Layout.fillWidth: true
                Layout.preferredHeight: overlay.lyricsHeight
                visible: overlay.showLyrics
                clip: true
                interactive: false
                model: TidalLyrics.lines
                currentIndex: TidalLyrics.currentIndex
                highlight: Item {}
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: height / 2 - 10
                preferredHighlightEnd:   height / 2 + 10
                highlightMoveDuration: 350
                highlightMoveVelocity: -1
                spacing: 4

                delegate: Text {
                    required property var modelData
                    required property int index
                    width: lyricsList.width
                    textFormat: Text.StyledText
                    text: TidalLyrics.styledLine(modelData.text, index, Theme.accent)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: index === TidalLyrics.currentIndex ? Theme.clrText : Theme.clrSubtext0
                    opacity: index === TidalLyrics.currentIndex ? 1.0 : 0.55
                    font {
                        family: overlay.nfFont; pixelSize: 12
                        bold: index === TidalLyrics.currentIndex
                    }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }
        }
    }
}
