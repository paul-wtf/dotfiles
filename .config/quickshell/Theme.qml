pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ── Aktive Variante ──────────────────────────────────────────────
    property string variant: "zen"                    // "mocha" | "liquidglass" | "zen" — Default: zen
    readonly property var  variants: ["mocha", "liquidglass", "zen"]
    readonly property bool glass: variant === "liquidglass"
    readonly property bool zen:   variant === "zen"

    readonly property string stateDir:
        (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property string statePath: stateDir + "/theme"

    function setVariant(name) {
        if (variants.indexOf(name) === -1)
            return
        variant = name
        stateFile.setText(name + "\n")
    }

    // Rotiert durch alle Varianten: mocha → liquidglass → zen → mocha
    function toggle() {
        setVariant(variants[(variants.indexOf(variant) + 1) % variants.length])
    }

    // ── Persistenz: einmal lesen beim Start, schreiben bei Änderung ───
    Process { command: ["mkdir", "-p", root.stateDir]; running: true }

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false                            // fehlende Datei beim Erststart ist ok
        onLoaded: {
            const t = text().trim()
            if (root.variants.indexOf(t) !== -1)
                root.variant = t
        }
    }

    // ── Glas-spezifische Token ───────────────────────────────────────
    // Im Glas-Look bleibt die Border in der Sky/Aqua-Tönung des Mocha-Themes,
    // aber deutlich weicher (Alpha ~0.4×), damit sie nicht dominiert.
    // In Zen sind alle Border-Breiten 0 — der Rückgabewert ist dort egal.
    function borderColor(a) {
        return glass ? Qt.rgba(0.72, 0.94, 1.00, a * 0.85)
                     : Qt.rgba(0.537, 0.863, 0.922, a)
    }

    // Aqua-getönte, durchscheinende Glasfläche (statt reinem Weiß) – wirkt erst
    // mit Compositor-Blur als frosted Glass. Zen: opakes Mantle — Bar, Frame
    // und angedockte Overlays sind EINE Fläche.
    readonly property color panelBg: zen ? "#181825"
                                   : glass ? Qt.rgba(0.45, 0.80, 0.85, 0.32) : "#1e1e2e"
    // Tiefere Variante für Panels, die im Mocha-Look auf clrMantle saßen
    // (SidePanel, Notification). Im Glas-Look identisch zu panelBg.
    readonly property color panelBgDeep: zen ? "#181825"
                                       : glass ? Qt.rgba(0.45, 0.80, 0.85, 0.32) : "#181825"
    readonly property color rim:     glass ? Qt.rgba(0.70, 0.95, 1.00, 0.25) : "transparent"
    readonly property int   radius:  zen ? 20 : glass ? 16 : 12
    readonly property color accent:  zen ? "#94e2d5" : glass ? "#88d8ff" : "#89dceb"
    // Oberer Farbstopp des Audio-Visualizer-Gradienten (heller Sky-Highlight).
    readonly property color vizBarTop: glass ? Qt.rgba(0.80, 0.96, 1.00, 1.0) : "#c8eef5"

    // ── Semantische Palette (Namen wie im Altcode) ───────────────────
    readonly property color clrCrust:    "#11111b"
    readonly property color clrBase:     glass ? "#0b0814"            : "#1e1e2e"

    readonly property color clrSurface0: glass ? Qt.rgba(0.45,0.80,0.85,0.26) : "#313244"
    readonly property color clrSurface1: glass ? Qt.rgba(0.55,0.88,0.92,0.18) : "#45475a"
    readonly property color clrText:     glass ? Qt.rgba(1,1,1,0.94)  : "#cdd6f4"
    readonly property color clrSubtext0: glass ? Qt.rgba(1,1,1,0.62)  : "#a6adc8"
    readonly property color clrSubtext1: glass ? Qt.rgba(1,1,1,0.78)  : "#bac2de"
    readonly property color clrBlue:     glass ? "#9cd2ff"            : "#89b4fa"

    readonly property color clrGreen:    glass ? "#86efac"            : "#a6e3a1"
    readonly property color clrYellow:   glass ? "#fde68a"            : "#f9e2af"
    readonly property color clrPeach:    glass ? "#fdba74"            : "#fab387"
    readonly property color clrRed:      glass ? "#fca5a5"            : "#f38ba8"
    readonly property color clrTeal:     glass ? "#5eead4"            : "#94e2d5"
    readonly property color clrSky:      glass ? "#88d8ff"            : "#89dceb"
    readonly property color clrSapphire: glass ? "#7dd3fc"            : "#74c7ec"
    readonly property color clrMauve:    glass ? "#d8b4fe"            : "#cba6f7"
    readonly property color clrPink:     glass ? "#f9a8d4"            : "#f5c2e7"

    // ── Zen: Bar & Inseln ─────────────────────────────────────────────
    // Zen: die Bar SELBST ist die Fläche (Mantle, volle Breite, keine Margins);
    // die Inseln werden zu unsichtbaren Layout-Containern.
    readonly property color barBg:            zen ? "#181825" : "transparent"
    readonly property int   barMargin:        zen ? 0  : 10
    readonly property int   barHeight:        44
    readonly property color islandBg:         zen ? "transparent" : panelBg
    readonly property int   islandBorderWidth: zen ? 0 : 2
    readonly property bool  sepVisible:       !zen

    // ── Zen: Farbdisziplin ────────────────────────────────────────────
    // Statt Regenbogen-Stats: Icons teal, Uhr sky, kritisches rot — sonst nichts.
    function statIcon(fallback) { return zen ? clrTeal : fallback }
    readonly property color clockColor: zen ? clrSky  : clrPink
    readonly property color wsActiveBg: zen ? clrTeal : clrSky
    readonly property color wsActiveFg: zen ? clrCrust : clrBase

    // ── Zen: Overlays & Panels ────────────────────────────────────────
    readonly property int   panelRadius:        zen ? 20 : 16       // SidePanel-Ecken
    readonly property int   overlayBorderWidth: zen ? 0  : 2        // Music/Stats
    readonly property int   overlayTop:         zen ? 44 : 58       // Fensterabstand oben
    readonly property color notifBg:            zen ? "#1e1e2e" : panelBgDeep
    readonly property int   notifBorderWidth:   zen ? 0  : 1
    readonly property int   notifRadius:        zen ? 16 : radius
    readonly property int   notifTop:           zen ? 54 : 56
    readonly property int   notifRight:         zen ? 18 : 14
    readonly property int   sidePanelBorderWidth: zen ? 0 : 1
    readonly property int   sidePanelMarginTop:   zen ? 0 : 8
    readonly property int   sidePanelMarginLeft:  zen ? 0 : 12
    readonly property int   sidePanelMarginBottom: zen ? 0 : 8
    readonly property int   dismissLeft:        zen ? 304 : 316     // SidePanel-Breite + Margin + Puffer
    readonly property color searchBg:           zen ? "#1e1e2e" : "#181825"
    readonly property int   searchBorderWidth:  zen ? 0  : 2
    readonly property int   searchRadius:       zen ? 20 : 16

    // ── Zen: Frame & Viewport ─────────────────────────────────────────
    readonly property int  frameThickness: 10
    readonly property int  viewportRadius: 16
    readonly property int  filletSize:     12    // konkave Flares an Panel-Oberkanten
    readonly property bool shadowEnabled:  zen   // weicher Schatten nur auf freien Cards

    // ── Zen: Motion ───────────────────────────────────────────────────
    readonly property int durFast:   200   // Farbe/Opacity
    readonly property int durNormal: 350   // Position/Größe (mit Überschwingen)

    // ── Hyprland-Kopplung ─────────────────────────────────────────────
    // Zen passt die Fenster-Deko an (Gaps machen Platz für den Frame, solider
    // Teal-Border statt rotierendem Gradient, Rounding harmonisiert mit dem
    // Viewport). Zen-Werte MÜSSEN zu den Defaults in ~/git/nixos/home/
    // program-configs/linux/hyprland.nix passen (zen ist Default-Variante);
    // Restore = Alt-Werte für mocha/liquidglass. Läuft auch beim Start →
    // selbstheilend.
    // Hyprland 0.57 entfernt das .conf-Format; die NixOS-Config läuft seit der
    // Migration auf Hyprlands Lua-Format. Unter dem Lua-Config-Manager antwortet
    // `hyprctl keyword` nur noch mit "keyword can't work with non-legacy parsers.
    // Use eval." (dispatchKeyword ist auf CONFIG_LEGACY gegated) → stattdessen
    // ein hl.config()-Aufruf durch `hyprctl eval`. Ein einziger Aufruf statt
    // --batch, weil hl.config ohnehin ein verschachteltes Table nimmt.
    // Farben in einfachen Anführungszeichen: Lua-Strings, so bleibt das
    // umschließende QML-String-Literal frei von Escapes.
    readonly property string hyprZen:
        "hl.config({ " +
        "general = { gaps_out = { top = 12, right = 22, bottom = 22, left = 22 }, " +
        "col = { active_border = 'rgb(94e2d5)' } }, " +
        "decoration = { rounding = 12, glow = { enabled = false } } }); " +
        "hl.animation({ leaf = 'borderangle', enabled = false }); " +
        "hl.animation({ leaf = 'glowangle', enabled = false })"
    readonly property string hyprRestore:
        "hl.config({ " +
        "general = { gaps_out = 10, " +
        "col = { active_border = { colors = { 'rgb(89dceb)', 'rgb(94e2d5)' }, angle = 45 } } }, " +
        "decoration = { rounding = 10, glow = { enabled = true } } }); " +
        "hl.animation({ leaf = 'borderangle', enabled = true, speed = 60, bezier = 'linear', style = 'loop' }); " +
        "hl.animation({ leaf = 'glowangle', enabled = true, speed = 60, bezier = 'linear', style = 'loop' })"

    Process {
        id: hyprProc
        // command wird vor jedem Start neu gesetzt; running wird davor explizit
        // zurückgesetzt, denn true→true wäre ein No-Op und würde den neuen
        // Batch verwerfen (schneller Doppel-Toggle).
    }
    function applyHyprland() {
        // Absichtlich variant === "zen" statt der readonly-property "zen":
        // beim Feuern von onVariantChanged ist die abhängige Bindung "zen"
        // hier noch nicht aktualisiert (ein Tick stale in beide Richtungen),
        // dadurch würde sonst immer der VORHERIGE Zustand angewendet.
        hyprProc.running = false
        hyprProc.command = ["hyprctl", "eval", variant === "zen" ? hyprZen : hyprRestore]
        hyprProc.running = true
    }

    // Rofi folgt der Variante über einen Symlink; ~/.config/rofi/config.rasi
    // bindet ihn ein. Liquidglass nutzt das Mocha-Rasi (kein eigenes Glas-Rofi).
    // command wird vor jedem Start neu gesetzt; running wird davor explizit
    // zurückgesetzt, denn true→true wäre ein No-Op und würde den neuen
    // Batch verwerfen (schneller Doppel-Toggle).
    Process { id: rofiLinkProc }
    function applyRofiTheme() {
        // variant statt zen: abgeleitete Properties sind im onVariantChanged-
        // Handler noch einen Tick alt (siehe applyHyprland).
        var target = (variant === "zen") ? "catppuccin-zen.rasi" : "catppuccin-mocha.rasi"
        rofiLinkProc.running = false
        // Fester Pfad ~/.local/state statt stateDir: config.rasi und
        // theme-switch.sh können XDG_STATE_HOME nicht expandieren — der fixe
        // Pfad ist der gemeinsame Vertrag. mkdir eingefaltet, weil beim
        // allerersten Start das Verzeichnis noch fehlen kann (Race mit dem
        // asynchronen mkdir-Process oben). Außer den zwei bekannten
        // Dateinamen ist nichts dynamisch — kein Quoting-Risiko.
        rofiLinkProc.command = ["/bin/sh", "-c",
            "mkdir -p \"$HOME/.local/state/quickshell\" && " +
            "ln -sfn \"$HOME/.config/rofi/" + target + "\" \"$HOME/.local/state/quickshell/rofi-theme.rasi\""]
        rofiLinkProc.running = true
    }

    onVariantChanged: { applyHyprland(); applyRofiTheme() }
    Component.onCompleted: { applyHyprland(); applyRofiTheme() }
}
