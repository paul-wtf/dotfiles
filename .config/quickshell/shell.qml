//@ pragma UseQApplication
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    property bool sidePanelOpen:  false
    property bool statsOpen:      false
    property bool musicOpen:      false
    property bool claudeOpen:     false

    // Hidden layers still commit, and every commit makes Hyprland present an
    // extra frame, which breaks VRR under a fullscreen game.
    readonly property bool mainFullscreen:
        Hyprland.monitorFor(mainBar.screen)?.activeWorkspace?.hasFullscreen ?? false

    // ── Notifications ───────────────────────────────────────────────────────────
    // Einziger Server (besitzt org.freedesktop.Notifications). Eingehende
    // Notifications müssen explizit getrackt werden, sonst werden sie sofort
    // verworfen. trackedNotifications speist SidePanel-Verlauf + Popups.
    NotificationServer {
        id: notifServer
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: false
        onNotification: (notification) => { notification.tracked = true }
    }

    // ── Theme-Umschaltung via IPC ───────────────────────────────────────────────
    // qs ipc call theme toggle   /   qs ipc call theme setVariant liquidglass
    IpcHandler {
        target: "theme"
        function toggle(): void { Theme.toggle() }
        function setVariant(name: string): void { Theme.setVariant(name) }
    }

    Bar {
        id: mainBar
        visible: !root.mainFullscreen
        onPanelToggled: root.sidePanelOpen = !root.sidePanelOpen
        onStatsToggled: root.statsOpen     = !root.statsOpen
        onMusicToggled: root.musicOpen     = !root.musicOpen
        onClaudeToggled: root.claudeOpen   = !root.claudeOpen
    }

    Frame { visible: Theme.zen && !root.mainFullscreen }

    SidePanel {
        panelOpen: root.sidePanelOpen
        notifServer: notifServer
        onCloseRequested: root.sidePanelOpen = false
    }

    NotificationPopup {
        notifServer: notifServer
        barScreen:   mainBar.screen
    }

    StatsOverlay {
        visible:        !root.mainFullscreen
        statsOpen:      root.statsOpen
        panelWidth:     mainBar.centerIslandWidth

        cpuUsage:  mainBar.cpuUsage
        cpuClock:  mainBar.cpuClock
        cpuPower:  mainBar.cpuPower
        cpuTemp:   mainBar.cpuTemp
        ramUsed:   mainBar.ramUsed
        gpuUsage:  mainBar.gpuUsage
        gpuClock:  mainBar.gpuClock
        gpuPower:  mainBar.gpuPower
        gpuTemp:   mainBar.gpuTemp
        gpuVram:   mainBar.gpuVram
        netDown:   mainBar.netDown
        netUp:     mainBar.netUp

        cpuHistory:     mainBar.cpuHistory
        gpuHistory:     mainBar.gpuHistory
        ramHistory:     mainBar.ramHistory
        netDownHistory: mainBar.netDownHistory
        netDownMax:     mainBar.netDownMax
    }

    MusicOverlay {
        visible:       !root.mainFullscreen
        musicOpen:     root.musicOpen
        islandX:       mainBar.musicIslandX
        islandWidth:   mainBar.musicIslandWidth
        player:        mainBar.activePlayer
        trackPosition: mainBar.trackPosition
        trackLength:   mainBar.trackLength
    }

    ClaudeOverlay {
        visible:     !root.mainFullscreen
        claudeOpen:  root.claudeOpen
        islandX:     mainBar.claudeIslandX
        islandWidth: mainBar.claudeIslandWidth
        limits:      mainBar.claudeLimits
        tokens:      mainBar.claudeTokens
        fetchedAt:   mainBar.claudeFetchedAt
        stale:       mainBar.claudeStale
    }

    // Klick außerhalb schließt ClaudeOverlay
    PanelWindow {
        screen: mainBar.screen
        anchors { top: true; left: true; right: true; bottom: true }
        margins { top: Theme.overlayTop }
        exclusiveZone: -1
        color: "transparent"
        visible: root.claudeOpen
        MouseArea {
            anchors.fill: parent
            onClicked: root.claudeOpen = false
        }
    }

    // Klick außerhalb schließt MusicOverlay
    PanelWindow {
        screen: mainBar.screen
        anchors { top: true; left: true; right: true; bottom: true }
        margins { top: Theme.overlayTop }
        exclusiveZone: -1
        color: "transparent"
        visible: root.musicOpen
        MouseArea {
            anchors.fill: parent
            onClicked: root.musicOpen = false
        }
    }

    // Klick außerhalb schließt StatsOverlay
    PanelWindow {
        screen: mainBar.screen
        anchors { top: true; left: true; right: true; bottom: true }
        margins { top: Theme.overlayTop }
        exclusiveZone: -1
        color: "transparent"
        visible: root.statsOpen
        MouseArea {
            anchors.fill: parent
            onClicked: root.statsOpen = false
        }
    }

    // Dismiss overlay for SidePanel
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        margins {
            left: Theme.dismissLeft
        }
        exclusiveZone: -1
        color: "transparent"
        visible: root.sidePanelOpen
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.sidePanelOpen = false
            }
        }
    }
}
