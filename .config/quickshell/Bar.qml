import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

PanelWindow {
    id: bar

    signal panelToggled()

    Process {
        id: rofiProc
        command: ["rofi", "-show", "drun"]
    }

    function launchRofi() { rofiProc.running = true }

    // ── Screen ───────────────────────────────────────────────────────────────
    screen: {
        for (var i = 0; i < Quickshell.screens.length; i++)
            if (Quickshell.screens[i].name === "HDMI-A-1")
                return Quickshell.screens[i]
        return Quickshell.screens[0]
    }

    anchors { top: true; left: true; right: true }
    margins { top: Theme.barMargin; left: Theme.barMargin; right: Theme.barMargin }
    implicitHeight: Theme.barHeight
    exclusiveZone:  Theme.barHeight
    color: Theme.barBg

    // ── Stats state ──────────────────────────────────────────────────────────
    property string cpuUsage:  "0"
    property string cpuClock:  "0MHz"
    property string cpuPower:  "0W"
    property string cpuTemp:   "0"
    property string ramUsed:   "0.0"
    property string gpuUsage:  "0"
    property string gpuClock:  "0MHz"
    property string gpuPower:  "0W"
    property string gpuTemp:   "0"
    property string gpuVram:   "0M"
    property string netDown:   "0K"
    property string netUp:     "0K"
    property string clockTime:   Qt.formatTime(new Date(), "hh:mm")
    property string windowTitle: ""

    // ── Host ─────────────────────────────────────────────────────────────────
    // Auf dem Laptop wird die Media-Island ausgeblendet (zu wenig Platz).
    property bool isLaptop: false
    Process {
        id: hostnameProc
        command: ["/bin/sh", "-c", "hostname"]
        running: true
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.isLaptop = (d.trim() === "paul-laptop") } }
    }

    // ── Battery (nur Laptop) ───────────────────────────────────────────────────
    property int    batteryCapacity:   -1   // -1 = kein Akku / noch nicht gelesen
    property string batteryStatus:     ""   // Charging / Discharging / Full / Not charging
    property real   batteryEnergyNow:  0    // µWh
    property real   batteryEnergyFull: 0    // µWh
    property var    batteryPowerHistory: [] // letzte Leistungswerte (µW) fuer die Glaettung
    readonly property bool batteryCharging: batteryStatus === "Charging" || batteryStatus === "Full"

    // Geglaettete Leistung in Watt (gleitender Mittel ueber die History). Battery-
    // Leistung schwankt stark; der Mittelwert beruhigt Anzeige und Schaetzung.
    readonly property real batteryPowerW: {
        var h = batteryPowerHistory
        if (h.length === 0) return 0
        var sum = 0
        for (var i = 0; i < h.length; i++) sum += h[i]
        return (sum / h.length) / 1e6
    }

    // Restlaufzeit in Minuten aus geglaetteter Leistung; -1 = unbekannt.
    readonly property int batteryMinutes: {
        if (batteryPowerW <= 0) return -1
        var pw = batteryPowerW * 1e6   // zurueck in µW
        if (batteryStatus === "Discharging" && batteryEnergyNow > 0)
            return Math.round(batteryEnergyNow / pw * 60)
        if (batteryStatus === "Charging" && batteryEnergyFull > batteryEnergyNow)
            return Math.round((batteryEnergyFull - batteryEnergyNow) / pw * 60)
        return -1
    }

    // Restlaufzeit als "1h 41m". Leer, wenn keine Schaetzung moeglich.
    readonly property string batteryTimeText: {
        if (batteryMinutes < 0) return ""
        var h = Math.floor(batteryMinutes / 60)
        var m = batteryMinutes % 60
        var t = h > 0 ? (h + "h " + m + "m") : (m + "m")
        return batteryCharging ? (t + " bis voll") : ("~" + t + " übrig")
    }

    readonly property string batteryIcon: {
        if (batteryCapacity < 0) return ""
        if (batteryCharging)     return "󰂄"   // Ladeblitz
        var lvls = ["󰂎","󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"]  // 0..100 in 10%-Schritten
        var idx = Math.round(batteryCapacity / 10)
        return lvls[Math.max(0, Math.min(10, idx))]
    }
    readonly property color batteryColor: {
        if (batteryCharging)         return Theme.clrGreen
        if (batteryCapacity <= 15)   return Theme.clrRed
        if (batteryCapacity <= 30)   return Theme.clrYellow
        return Theme.clrText
    }

    // ── Graph history ────────────────────────────────────────────────────────
    signal statsToggled()
    readonly property real centerIslandWidth: centerIsland.width

    // ── Music overlay ─────────────────────────────────────────────────────────
    signal musicToggled()
    readonly property real musicIslandX:     musicIsland.x
    readonly property real musicIslandWidth: musicIsland.width

    // ── Claude usage ─────────────────────────────────────────────────────────
    signal claudeToggled()
    readonly property real claudeIslandX:     claudeIsland.x
    readonly property real claudeIslandWidth: claudeIsland.width
    property var  claudeLimits:    []
    property var  claudeStats:     null
    property int  claudeFetchedAt: 0
    property bool claudeStale:     false

    function claudePercent(label) {
        for (var i = 0; i < claudeLimits.length; i++)
            if (claudeLimits[i].label === label) return Math.round(claudeLimits[i].percent) + "%"
        return "–"
    }
    readonly property color claudeColor: {
        var c = Theme.clrText
        for (var i = 0; i < claudeLimits.length; i++) {
            var s = claudeLimits[i].severity
            if (s === "warning") c = Theme.clrYellow
            else if (s !== "normal") return Theme.clrRed
        }
        return c
    }

    readonly property string claudeScript:
        Qt.resolvedUrl("scripts/claude-usage.py").toString().replace("file://", "")
    Process {
        id: claudeStatsProc
        command: ["python3", bar.claudeScript, "stats"]
        running: true
        stdout: SplitParser { splitMarker: "\n"; onRead: d => {
            try { bar.claudeStats = JSON.parse(d) } catch (e) {} } }
    }
    Process {
        id: claudeLimitsProc
        command: ["python3", bar.claudeScript, "limits"]
        running: true
        stdout: SplitParser { splitMarker: "\n"; onRead: d => {
            try {
                var r = JSON.parse(d)
                bar.claudeStale = !r.ok
                if (r.ok) { bar.claudeLimits = r.limits; bar.claudeFetchedAt = r.fetched_at }
            } catch (e) {} } }
    }
    Timer {
        interval: 120000; running: true; repeat: true
        onTriggered: if (!claudeStatsProc.running) claudeStatsProc.running = true
    }
    // The usage endpoint is rate-limited.
    Timer {
        interval: 300000; running: true; repeat: true
        onTriggered: if (!claudeLimitsProc.running) claudeLimitsProc.running = true
    }
    property var  cpuHistory:      []
    property var  gpuHistory:      []
    property var  ramHistory:      []
    property var  netDownHistory:  []

    property real netDownMax: {
        if (netDownHistory.length === 0) return 1000
        var m = 1
        for (var i = 0; i < netDownHistory.length; i++)
            if (netDownHistory[i] > m) m = netDownHistory[i]
        return m * 1.2
    }

    function appendHistory(arr, val) {
        var a = arr.slice()
        a.push(val)
        if (a.length > 60) a.shift()
        return a
    }

    function parseNetKB(s) {
        if (!s) return 0
        var n = parseFloat(s) || 0
        if (s.indexOf("G") !== -1) return n * 1024 * 1024
        if (s.indexOf("M") !== -1) return n * 1024
        return n
    }

    // ── Visualizer state ─────────────────────────────────────────────────────
    property var  barValues:   []
    property bool hasAudio:    false
    property real silenceSecs: 0

    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            var loud = bar.barValues.some(v => v > 2)
            if (loud) {
                bar.hasAudio    = true
                bar.silenceSecs = 0
            } else {
                bar.silenceSecs += 0.5
                if (bar.silenceSecs >= 4) bar.hasAudio = false
            }
        }
    }

    Process {
        id: cavaProc
        command: ["cava", "-p",
                  Qt.resolvedUrl("scripts/cava-bar.ini").toString().replace("file://", "")]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: d => {
                var parts = d.trim().split(" ")
                if (parts.length > 1)
                    bar.barValues = parts.map(v => Math.max(0, parseInt(v) || 0))
            }
        }
        onRunningChanged: if (!running) cavaRestartTimer.restart()
    }

    Timer {
        id: cavaRestartTimer
        interval: 1000
        repeat: false
        onTriggered: cavaProc.running = true
    }

    // ── MPRIS ─────────────────────────────────────────────────────────────────
    property var activePlayer: {
        var list = Mpris.players.values ?? Mpris.players
        // 1. Spotify playing
        for (var i = 0; i < list.length; i++)
            if (list[i].identity?.toLowerCase().includes("spotify") &&
                list[i].playbackState === MprisPlaybackState.Playing) return list[i]
        // 2. Any other source playing
        for (var i = 0; i < list.length; i++)
            if (list[i].playbackState === MprisPlaybackState.Playing) return list[i]
        // 3. Spotify paused
        for (var i = 0; i < list.length; i++)
            if (list[i].identity?.toLowerCase().includes("spotify")) return list[i]
        // 4. First available
        return list.length > 0 ? list[0] : null
    }
    property string songText: {
        if (!activePlayer) return ""
        var t = activePlayer.trackTitle  || ""
        var a = activePlayer.trackArtist || ""
        if (a && t) return a + "  –  " + t
        return t || a
    }

    property real trackPosition: 0
    property real trackLength:   activePlayer ? (activePlayer.length ?? 0) : 0

    onActivePlayerChanged: trackPosition = activePlayer ? (activePlayer.position ?? 0) : 0

    // Tick position forward every second while playing
    Timer {
        interval: 1000; repeat: true
        running: bar.activePlayer !== null &&
                 bar.activePlayer.playbackState === MprisPlaybackState.Playing
        onTriggered: {
            if (bar.activePlayer)
                bar.trackPosition = bar.activePlayer.position ?? (bar.trackPosition + 1)
        }
    }

    function formatTime(s) {
        if (!s || s <= 0) return "0:00"
        s = Math.floor(s)
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: bar.clockTime = Qt.formatTime(new Date(), "hh:mm")
    }

    // ── Stat processes ───────────────────────────────────────────────────────
    Process {
        id: cpuUsageProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/cpu-usage.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) { bar.cpuUsage = d.trim(); bar.cpuHistory = bar.appendHistory(bar.cpuHistory, parseFloat(d.trim()) || 0) } } }
    }
    Process {
        id: cpuClockProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/cpu-clock.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.cpuClock = d.trim() } }
    }
    Process {
        id: cpuPowerProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/cpu-power.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.cpuPower = d.trim() } }
    }
    Process {
        id: cpuTempProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/cpu-temp.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.cpuTemp = d.trim() } }
    }
    Process {
        id: ramProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/ram.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) { bar.ramUsed = d.trim(); bar.ramHistory = bar.appendHistory(bar.ramHistory, parseFloat(d.trim()) || 0) } } }
    }
    Process {
        id: gpuUsageProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/gpu-usage.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) { bar.gpuUsage = d.trim(); bar.gpuHistory = bar.appendHistory(bar.gpuHistory, parseFloat(d.trim()) || 0) } } }
    }
    Process {
        id: gpuClockProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/gpu-clock.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.gpuClock = d.trim() } }
    }
    Process {
        id: gpuPowerProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/gpu-power.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.gpuPower = d.trim() + "W" } }
    }
    Process {
        id: gpuTempProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/gpu-temp.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.gpuTemp = d.trim() } }
    }
    Process {
        id: gpuVramProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/gpu-vram.sh").toString().replace("file://", "")]
        stdout: SplitParser { splitMarker: "\n"; onRead: d => { if (d.trim()) bar.gpuVram = d.trim() } }
    }
    Process {
        id: netProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/net.sh").toString().replace("file://", "")]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: d => {
                if (!d.trim()) return
                var parts = d.trim().split(" ")
                if (parts.length >= 2) {
                    bar.netDown = parts[0]
                    bar.netUp   = parts[1]
                    bar.netDownHistory = bar.appendHistory(bar.netDownHistory, bar.parseNetKB(parts[0]))
                }
            }
        }
    }

    // ── Battery (nur Laptop; auf dem Desktop liefert das Skript nichts) ────────
    Process {
        id: batteryProc
        command: ["/bin/sh", Qt.resolvedUrl("scripts/battery.sh").toString().replace("file://", "")]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: d => {
                if (!d.trim()) return
                var parts = d.trim().split(" ")
                bar.batteryCapacity   = parseInt(parts[0])
                bar.batteryStatus     = parts[1] || ""
                var pw = parts.length > 2 ? (parseFloat(parts[2]) || 0) : 0   // µW
                bar.batteryEnergyNow  = parts.length > 3 ? (parseFloat(parts[3]) || 0) : 0
                bar.batteryEnergyFull = parts.length > 4 ? (parseFloat(parts[4]) || 0) : 0
                if (pw > 0) {
                    var h = bar.batteryPowerHistory.slice()
                    h.push(pw)
                    while (h.length > 15) h.shift()   // ~30 s Fenster (Poll alle 2 s)
                    bar.batteryPowerHistory = h
                }
            }
        }
    }

    // ── Active window title ───────────────────────────────────────────────────
    Process {
        id: winTitleProc
        command: ["sh", "-c", "hyprctl activewindow -j | jq -r '.title // empty'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: d => { bar.windowTitle = d.trim() }
        }
    }

    Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: {
            if (!cpuUsageProc.running) cpuUsageProc.running = true
            if (!cpuClockProc.running) cpuClockProc.running = true
            if (!cpuPowerProc.running) cpuPowerProc.running = true
            if (!cpuTempProc.running)  cpuTempProc.running  = true
            if (!ramProc.running)      ramProc.running      = true
            if (!gpuUsageProc.running) gpuUsageProc.running = true
            if (!gpuClockProc.running) gpuClockProc.running = true
            if (!gpuPowerProc.running) gpuPowerProc.running = true
            if (!gpuTempProc.running)  gpuTempProc.running  = true
            if (!gpuVramProc.running)  gpuVramProc.running  = true
            if (!netProc.running)      netProc.running      = true
            if (!batteryProc.running)  batteryProc.running  = true
            if (!winTitleProc.running) winTitleProc.running = true
        }
    }

    Component.onCompleted: {
        cpuUsageProc.running = true
        cpuClockProc.running = true
        cpuPowerProc.running = true
        cpuTempProc.running  = true
        ramProc.running      = true
        gpuUsageProc.running = true
        gpuClockProc.running = true
        gpuPowerProc.running = true
        gpuTempProc.running  = true
        gpuVramProc.running  = true
        netProc.running      = true
        batteryProc.running  = true
        winTitleProc.running = true
    }

    // ── Layout ───────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent

        // ── Left island: Workspaces + Buttons ───────────────────────────────
        Rectangle {
            id: leftIsland
            anchors { left: parent.left; top: parent.top; topMargin: 2 }
            height: 40
            radius: Theme.radius
            color: Theme.islandBg
            border { color: Theme.borderColor(0.55); width: Theme.islandBorderWidth }
            clip: true
            width: leftRow.implicitWidth + 16

            RowLayout {
                id: leftRow
                anchors.centerIn: parent
                spacing: 4

                // Gemeinsames, sortiertes Workspace-Modell (IDs 1–10)
                Item {
                    id: wsHolder
                    property var wsList: {
                        var ws = []
                        var all = Hyprland.workspaces.values
                        for (var i = 0; i < all.length; i++) {
                            var w = all[i]
                            if (w.id >= 1 && w.id <= 10) ws.push(w)
                        }
                        ws.sort(function(a, b) { return a.id - b.id })
                        return ws
                    }
                    property int activeIdx: {
                        var act = Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace
                                  ? Hyprland.focusedMonitor.activeWorkspace.id : -1
                        for (var i = 0; i < wsList.length; i++)
                            if (wsList[i].id === act) return i
                        return -1
                    }
                    visible: false
                }

                // ── Klassische Pills (Mocha / Liquidglass) ────────────────────
                Row {
                    spacing: 4
                    visible: !Theme.zen
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: wsHolder.wsList
                        delegate: Rectangle {
                            required property var modelData
                            property bool isActive: Hyprland.focusedMonitor &&
                                Hyprland.focusedMonitor.activeWorkspace &&
                                Hyprland.focusedMonitor.activeWorkspace.id === modelData.id
                            width: 28; height: 28
                            radius: 6
                            color: isActive ? Theme.clrSky : Theme.clrSurface0
                            Text {
                                anchors.centerIn: parent
                                text:  modelData.id
                                color: parent.isActive ? Theme.clrBase : Theme.clrSubtext0
                                font  { family: "JetBrainsMono Nerd Font"; pixelSize: 13; bold: parent.isActive }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: Hyprland.dispatch("workspace " + modelData.id)
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                    }
                }

                // ── Zen: Capsule mit gleitendem Teal-Indikator ────────────────
                Rectangle {
                    visible: Theme.zen
                    Layout.alignment: Qt.AlignVCenter
                    // implicit*, nicht width/height: das RowLayout layoutet nach
                    // impliziter Groesse und wuerde explizite Masse auf 0 druecken.
                    implicitWidth:  wsRow.width + 6
                    implicitHeight: 28
                    radius: height / 2
                    color:  Theme.clrSurface0

                    // Indikator hinter den Ziffern: gleitet mit Überschwingen
                    Rectangle {
                        id: wsIndicator
                        visible: wsHolder.activeIdx >= 0
                        x: 3 + wsHolder.activeIdx * (24 + 4)
                        y: 3
                        width: 22; height: 22
                        radius: height / 2
                        color: Theme.wsActiveBg
                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.durNormal
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.2
                            }
                        }
                    }

                    Row {
                        id: wsRow
                        x: 3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Repeater {
                            model: wsHolder.wsList
                            delegate: Item {
                                required property var modelData
                                required property int index
                                property bool isActive: index === wsHolder.activeIdx
                                width: 24; height: 22
                                Text {
                                    anchors.centerIn: parent
                                    text:  modelData.id
                                    color: parent.isActive ? Theme.wsActiveFg : Theme.clrSubtext0
                                    font  { family: "JetBrainsMono Nerd Font"; pixelSize: 12; bold: parent.isActive }
                                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Hyprland.dispatch("workspace " + modelData.id)
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }
                    }
                }

                // Side panel toggle
                BarButton {
                    icon:      "󰍜"
                    iconColor: Theme.statIcon(Theme.clrBlue)
                    onClicked: bar.panelToggled()
                }

                // Rofi launcher button
                BarButton {
                    icon:      "󰍉"
                    iconColor: Theme.statIcon(Theme.clrSky)
                    onClicked: bar.launchRofi()
                }
            }
        }

        // ── Window title island ───────────────────────────────────────────────
        Rectangle {
            id: windowIsland
            anchors { left: leftIsland.right; leftMargin: 8; top: parent.top; topMargin: 2 }
            height:  40
            radius:  Theme.radius
            color:   Theme.islandBg
            border   { color: Theme.borderColor(0.55); width: Theme.islandBorderWidth }
            visible: bar.windowTitle.length > 0
            implicitWidth: Math.min(winRow.implicitWidth + 20, 280)
            clip: true

            RowLayout {
                id: winRow
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text:  "󰖯"
                    color: Theme.statIcon(Theme.clrBlue)
                    font   { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                }
                Text {
                    text:  bar.windowTitle
                    color: Theme.clrText
                    font   { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                    elide: Text.ElideRight
                    Layout.maximumWidth: 230
                }
            }
        }

        // ── Music island: track + controls + progress + visualizer ───────────
        Rectangle {
            id: musicIsland
            anchors { right: rightIsland.left; rightMargin: 8; top: parent.top; topMargin: 2 }
            height:  40
            radius:  Theme.radius
            color:   Theme.islandBg
            border   { color: Theme.borderColor(0.55); width: Theme.islandBorderWidth }
            visible: bar.activePlayer !== null && !bar.isLaptop
            width:   musicRow.implicitWidth + 20

            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            RowLayout {
                id: musicRow
                anchors.centerIn: parent
                spacing: 8

                // Icon (klick öffnet Overlay)
                Text {
                    text:  "󰝚"
                    color: Theme.statIcon(Theme.clrMauve)
                    font   { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bar.musicToggled()
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                // Scrolling title (klick öffnet Overlay)
                Item {
                    id: titleClip
                    implicitWidth: 180
                    implicitHeight: scrollText.implicitHeight
                    clip: true
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: scrollText
                        text:  bar.songText
                        color: Theme.clrText
                        font   { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }

                        onTextChanged: {
                            scrollText.x = 0
                            marquee.stop()
                            marqueeDelay.restart()
                        }
                        Component.onCompleted: marqueeDelay.restart()
                    }

                    Timer {
                        id: marqueeDelay
                        interval: 100
                        onTriggered: {
                            if (scrollText.implicitWidth > titleClip.implicitWidth)
                                marquee.restart()
                        }
                    }

                    SequentialAnimation {
                        id: marquee
                        loops: Animation.Infinite
                        PauseAnimation   { duration: 2000 }
                        NumberAnimation  {
                            target: scrollText; property: "x"
                            to: -(scrollText.implicitWidth - titleClip.implicitWidth)
                            duration: Math.max(0, scrollText.implicitWidth - titleClip.implicitWidth) * 22
                            easing.type: Easing.Linear
                        }
                        PauseAnimation   { duration: 1500 }
                        NumberAnimation  {
                            target: scrollText; property: "x"
                            to: 0
                            duration: Math.max(0, scrollText.implicitWidth - titleClip.implicitWidth) * 22
                            easing.type: Easing.InOutCubic
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: bar.musicToggled()
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Rectangle { width: 1; height: 20; color: Theme.clrSurface1; visible: Theme.sepVisible }

                // Controls
                Text {
                    text: "󰒮"
                    color: Theme.clrSubtext0
                    font  { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (bar.activePlayer) bar.activePlayer.previous() }
                    }
                }
                Text {
                    text: (bar.activePlayer && bar.activePlayer.playbackState === MprisPlaybackState.Playing)
                          ? "󰏥" : "󰐊"
                    color: Theme.clrSky
                    font  { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!bar.activePlayer) return
                            if (bar.activePlayer.playbackState === MprisPlaybackState.Playing)
                                bar.activePlayer.pause()
                            else
                                bar.activePlayer.play()
                        }
                    }
                }
                Text {
                    text: "󰒭"
                    color: Theme.clrSubtext0
                    font  { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (bar.activePlayer) bar.activePlayer.next() }
                    }
                }

                Rectangle { width: 1; height: 20; color: Theme.clrSurface1; visible: Theme.sepVisible }

                // Progress
                Text {
                    text:  bar.formatTime(bar.trackPosition)
                    color: Theme.clrSubtext0
                    font   { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                }

                Item {
                    implicitWidth: 90
                    implicitHeight: 4
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Theme.clrSurface1
                    }
                    Rectangle {
                        width: bar.trackLength > 0
                               ? parent.width * Math.min(bar.trackPosition / bar.trackLength, 1)
                               : 0
                        height: parent.height
                        radius: 2
                        color: Theme.clrSky
                    }
                    MouseArea {
                        anchors { fill: parent; margins: -6 }
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (bar.activePlayer && bar.trackLength > 0) {
                                var pos = Math.max(0, Math.min(mouse.x / width, 1)) * bar.trackLength
                                bar.activePlayer.position = pos
                                bar.trackPosition = pos
                            }
                        }
                    }
                }

                Text {
                    text:  bar.formatTime(bar.trackLength)
                    color: Theme.clrSubtext0
                    font   { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                }

                Rectangle {
                    width: 1; height: 20; color: Theme.clrSurface1
                    visible: Theme.sepVisible && vizContainer.visible
                }

                // Visualizer
                Item {
                    id: vizContainer
                    implicitWidth:  vizBars.implicitWidth
                    implicitHeight: 26
                    opacity: bar.hasAudio ? 1.0 : 0.0
                    visible: opacity > 0
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on opacity { NumberAnimation { duration: 700 } }

                    Row {
                        id: vizBars
                        anchors.centerIn: parent
                        spacing: 1

                        Repeater {
                            model: bar.barValues.length > 0 ? Math.min(bar.barValues.length, 44) : 44
                            delegate: Item {
                                required property int index
                                width:  2
                                height: 26

                                property real val: (index < bar.barValues.length)
                                                   ? bar.barValues[index] / 100.0 : 0.0

                                Rectangle {
                                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                    width:  parent.width
                                    height: Math.max(2, parent.height * parent.val)
                                    radius: 1
                                    gradient: Gradient {
                                        orientation: Gradient.Vertical
                                        GradientStop { position: 0.0; color: Theme.vizBarTop }
                                        GradientStop { position: 1.0; color: Qt.rgba(Theme.clrSky.r, Theme.clrSky.g, Theme.clrSky.b, 0.4) }
                                    }
                                    Behavior on height { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Lyrics island: current and next line of the Tidal track ──────────
        Rectangle {
            id: lyricsIsland
            readonly property real room:
                (musicIsland.visible ? musicIsland.x : rightIsland.x) - 16
                - (centerIsland.x + centerIsland.width)
            anchors {
                right: musicIsland.visible ? musicIsland.left : rightIsland.left
                rightMargin: 8; top: parent.top; topMargin: 2
            }
            height:  40
            radius:  Theme.radius
            color:   Theme.islandBg
            border   { color: Theme.borderColor(0.55); width: Theme.islandBorderWidth }
            visible: !bar.isLaptop && TidalLyrics.synced && TidalLyrics.isTidal(bar.activePlayer) && room >= 200
            width:   Math.min(460, room)
            clip:    true

            ListView {
                id: barLyrics
                readonly property int rowHeight: 16
                anchors {
                    left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                height: rowHeight * 2 + spacing
                spacing: 1
                clip: true
                interactive: false
                model: TidalLyrics.lines
                currentIndex: TidalLyrics.currentIndex
                highlight: Item {}
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: 0
                preferredHighlightEnd: rowHeight
                highlightMoveDuration: 380
                highlightMoveVelocity: -1

                delegate: Item {
                    id: lyricRow
                    required property var modelData
                    required property int index
                    readonly property int  offset:  index - TidalLyrics.currentIndex
                    readonly property bool current: offset === 0
                    readonly property var  words:   modelData.text.split(/\s+/).filter(w => w.length > 0)
                    readonly property bool wordView: current && words.length > 0 && wordRow.implicitWidth <= width
                    width:   barLyrics.width
                    height:  barLyrics.rowHeight
                    opacity: current ? 1.0 : offset === 1 ? 0.6 : 0.0
                    scale:   current ? 1.0 : 0.9
                    Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutQuad } }
                    Behavior on scale   { NumberAnimation { duration: 380; easing.type: Easing.InOutQuad } }

                    Text {
                        anchors.fill: parent
                        visible: !lyricRow.wordView
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: TidalLyrics.styledLine(lyricRow.modelData.text, lyricRow.index, Theme.accent)
                        color: lyricRow.current ? Theme.clrText : Theme.clrSubtext0
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                        Behavior on color { ColorAnimation { duration: 380 } }
                    }

                    TextMetrics { id: spaceMetrics; font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 } text: " " }

                    Row {
                        id: wordRow
                        anchors.centerIn: parent
                        visible: lyricRow.wordView
                        spacing: spaceMetrics.advanceWidth

                        Repeater {
                            model: lyricRow.current ? lyricRow.words : []
                            delegate: Text {
                                id: word
                                required property string modelData
                                required property int index
                                readonly property bool active: index === TidalLyrics.wordIndex
                                property real glow: active ? 1.0 : 0.0
                                text: modelData
                                color: active ? Theme.accent : Theme.clrText
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; bold: active }
                                scale: active ? 1.18 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation  { duration: 160 } }
                                Behavior on glow  { NumberAnimation { duration: 220 } }
                                layer.enabled: glow > 0
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: Theme.accent
                                    shadowOpacity: word.glow
                                    shadowBlur: 0.7
                                    blurMax: 10
                                    shadowHorizontalOffset: 0
                                    shadowVerticalOffset: 0
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bar.musicToggled()
                cursorShape: Qt.PointingHandCursor
            }
        }

        // ── Claude island: plan limits ───────────────────────────────────────
        Rectangle {
            id: claudeIsland
            anchors {
                left: windowIsland.visible ? windowIsland.right : leftIsland.right
                leftMargin: 8; top: parent.top; topMargin: 2
            }
            height:  40
            radius:  Theme.radius
            color:   Theme.islandBg
            border   { color: Theme.borderColor(0.55); width: Theme.islandBorderWidth }
            visible: bar.claudeLimits.length > 0
            width:   claudeRow.implicitWidth + 20

            RowLayout {
                id: claudeRow
                anchors.centerIn: parent
                opacity: bar.claudeStale ? 0.5 : 1.0
                StatItem {
                    icon: "󰚩"
                    value: bar.claudePercent("Session") + " · " + bar.claudePercent("Woche")
                    iconColor: Theme.statIcon(Theme.clrPeach)
                    textColor: bar.claudeColor
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bar.claudeToggled()
                cursorShape: Qt.PointingHandCursor
            }
        }

        // ── Center island: Stats ─────────────────────────────────────────────
        Rectangle {
            id: centerIsland
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 2 }
            height: 40
            radius: Theme.radius
            color: Theme.islandBg
            border { color: Theme.borderColor(0.55); width: Theme.islandBorderWidth }
            width: statsRow.implicitWidth + 24

            RowLayout {
                id: statsRow
                anchors.centerIn: parent
                spacing: 14

                StatItem { icon: "󰻠"; value: bar.cpuUsage + "%"; valueChars: 4; iconColor: Theme.statIcon(Theme.clrGreen);   textColor: Theme.clrText }
                StatItem { icon: "󰓅"; value: bar.cpuClock;        valueChars: 7; iconColor: Theme.statIcon(Theme.clrSky);     textColor: Theme.clrText }
                StatItem { icon: "󱐋"; value: bar.cpuPower;        valueChars: 4; iconColor: Theme.statIcon(Theme.clrPeach);   textColor: Theme.clrText }
                StatItem { icon: "󰔏"; value: bar.cpuTemp + "°C";  valueChars: 4; iconColor: Theme.statIcon(Theme.clrYellow);  textColor: Theme.clrText }

                Rectangle { width: 1; height: 20; color: Theme.clrSurface1; visible: Theme.sepVisible }

                StatItem { icon: "󰍛"; value: bar.ramUsed + "G";   valueChars: 5; iconColor: Theme.statIcon(Theme.clrMauve);   textColor: Theme.clrText }

                Rectangle { width: 1; height: 20; color: Theme.clrSurface1; visible: Theme.sepVisible }

                StatItem { icon: "󰢮"; value: bar.gpuUsage + "%";  valueChars: 4; iconColor: Theme.statIcon(Theme.clrTeal);    textColor: Theme.clrText }
                StatItem { icon: "󰓅"; value: bar.gpuClock;         valueChars: 7; iconColor: Theme.statIcon(Theme.clrSky);     textColor: Theme.clrText }
                StatItem { icon: "󱐋"; value: bar.gpuPower;         valueChars: 4; iconColor: Theme.statIcon(Theme.clrPeach);   textColor: Theme.clrText }
                StatItem { icon: "󰔏"; value: bar.gpuTemp + "°C";   valueChars: 4; iconColor: Theme.statIcon(Theme.clrYellow);  textColor: Theme.clrText }
                StatItem { icon: "󰆧"; value: bar.gpuVram;          valueChars: 6; iconColor: Theme.statIcon(Theme.clrSky);     textColor: Theme.clrText }

                Rectangle { width: 1; height: 20; color: Theme.clrSurface1; visible: Theme.sepVisible }

                StatItem { icon: "󰁆"; value: bar.netDown; valueChars: 5; iconColor: Theme.statIcon(Theme.clrBlue);     textColor: Theme.clrText }
                StatItem { icon: "󰁞"; value: bar.netUp;   valueChars: 5; iconColor: Theme.statIcon(Theme.clrSapphire); textColor: Theme.clrText }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bar.statsToggled()
                cursorShape: Qt.PointingHandCursor
            }
        }

        // ── Right island: Tray + Clock + Power ──────────────────────────────
        Rectangle {
            id: rightIsland
            anchors { right: parent.right; top: parent.top; topMargin: 2 }
            height: 40
            radius: Theme.radius
            color: Theme.islandBg
            border { color: Theme.borderColor(0.55); width: Theme.islandBorderWidth }
            width: rightRow.implicitWidth + 16

            RowLayout {
                id: rightRow
                anchors.centerIn: parent
                spacing: 8

                // System Tray
                RowLayout {
                    spacing: 10
                    Layout.alignment: Qt.AlignVCenter
                    Repeater {
                        model: SystemTray.items
                        delegate: Item {
                            required property SystemTrayItem modelData
                            width: 20; height: 20
                            Layout.alignment: Qt.AlignVCenter
                            QsMenuAnchor {
                                id: trayMenu
                                menu: modelData.menu
                                anchor.window: bar
                            }
                            IconImage {
                                anchors.fill: parent
                                source: modelData.icon
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                                        var pos = mapToItem(bar.contentItem, 0, height)
                                        trayMenu.anchor.rect = Qt.rect(pos.x, pos.y, width, 0)
                                        trayMenu.open()
                                    } else {
                                        modelData.activate()
                                    }
                                }
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                    }
                }

                Rectangle { width: 1; height: 20; color: Theme.clrSurface1; visible: Theme.sepVisible }

                // Battery (nur Laptop): ein Modul, aber Prozent/Watt/Zeit durch
                // eigene Farbe (+ Blitz-Icon bei Watt) statt nur Leerzeichen getrennt.
                Row {
                    visible: bar.isLaptop && bar.batteryCapacity >= 0
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 10

                    Text {
                        text:  bar.batteryIcon + " " + bar.batteryCapacity + "%"
                        color: bar.batteryColor
                        font  { family: "JetBrainsMono Nerd Font"; pixelSize: 13; bold: true }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: bar.batteryPowerW > 0
                        text:  "󱐋 " + Math.round(bar.batteryPowerW) + "W"
                        color: Theme.clrPeach
                        font  { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: bar.batteryTimeText.length > 0
                        text:  bar.batteryTimeText
                        color: Theme.clrSubtext0
                        font  { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Rectangle {
                    visible: Theme.sepVisible && bar.isLaptop && bar.batteryCapacity >= 0
                    width: 1; height: 20; color: Theme.clrSurface1
                }

                // Clock
                Text {
                    text:  "󰃰 " + bar.clockTime
                    color: Theme.clockColor
                    font  { family: "JetBrainsMono Nerd Font"; pixelSize: 13; bold: true }
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle { width: 1; height: 20; color: Theme.clrSurface1; visible: Theme.sepVisible }

                // Power menu
                BarButton {
                    icon:      "󰐥"
                    iconColor: Theme.clrRed
                    onClicked: bar.powerMenu()
                }
            }
        }
    }

    function powerMenu() {
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { command: ["/bin/sh", "-c", "$HOME/.config/quickshell/scripts/powermenu.sh"] }',
            bar
        )
        proc.running = true
    }
}
