pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Synced lyrics of the current Tidal track, from the TidaLuna TidalAPI plugin.
Singleton {
    id: root

    readonly property string api: "http://127.0.0.1:24123"

    readonly property bool tidalRunning: {
        var list = Mpris.players.values ?? Mpris.players
        for (var i = 0; i < list.length; i++)
            if (isTidal(list[i])) return true
        return false
    }

    property string trackId:    ""
    property var    lines:      []
    property bool   playing:    false
    property real   positionMs: 0
    readonly property bool synced: lines.length > 0

    readonly property int currentIndex: {
        var idx = -1
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].time > positionMs) break
            idx = i
        }
        return idx
    }

    // Tidal only times whole lines: each word gets a share by length, at most msPerChar per
    // character, so a pause before the next line doesn't stretch the last words.
    readonly property real msPerChar: 75
    readonly property var currentWords: currentIndex >= 0 ? lines[currentIndex].text.split(/\s+/).filter(w => w.length > 0) : []
    readonly property int wordIndex: {
        var words = currentWords
        if (words.length === 0) return -1
        var start = lines[currentIndex].time
        var next = currentIndex + 1 < lines.length ? lines[currentIndex + 1].time : start + 5000
        var total = 0
        for (var i = 0; i < words.length; i++) total += words[i].length + 1
        var perUnit = Math.min(next - start, total * msPerChar) / total
        var elapsed = positionMs - start
        var acc = 0
        for (var j = 0; j < words.length; j++) {
            acc += (words[j].length + 1) * perUnit
            if (elapsed < acc) return j
        }
        return words.length - 1
    }

    property real _syncedMs: 0
    property real _syncedAt: 0
    property string _fetchedFor: ""

    function isTidal(player) {
        return !!player && (player.identity ?? "").toLowerCase().includes("tidal")
    }

    function escapeHtml(t) {
        return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function styledLine(text, index, accent) {
        if (text.length === 0) return "♪"
        if (index !== currentIndex) return escapeHtml(text)
        var words = currentWords
        var out = []
        for (var i = 0; i < words.length; i++)
            out.push(i === wordIndex
                ? "<font color=\"" + accent + "\">" + escapeHtml(words[i]) + "</font>"
                : escapeHtml(words[i]))
        return out.join(" ")
    }

    function parseLrc(text) {
        var out = []
        var rows = (text || "").split("\n")
        for (var i = 0; i < rows.length; i++) {
            var m = /^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$/.exec(rows[i])
            if (m) out.push({ time: (parseInt(m[1]) * 60 + parseFloat(m[2])) * 1000, text: m[3].trim() })
        }
        return out
    }

    function get(path, done) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var body = null
            if (xhr.status === 200) {
                try { body = JSON.parse(xhr.responseText) } catch (e) {}
            }
            done(xhr.status, body)
        }
        xhr.open("GET", api + path)
        xhr.send()
    }

    function reset() {
        trackId = ""
        lines = []
        playing = false
        _fetchedFor = ""
    }

    function poll() {
        get("/player", function(status, p) {
            if (!p) { reset(); return }
            playing = !!p.is_playing
            _syncedMs = p.progress_ms || 0
            _syncedAt = Date.now()
            positionMs = _syncedMs
            var id = p.item ? String(p.item.id) : ""
            if (id !== trackId) {
                trackId = id
                lines = []
                _fetchedFor = ""
            }
            if (id && _fetchedFor !== id) fetchLyrics(id)
        })
    }

    function fetchLyrics(id) {
        get("/tracks/" + id + "/lyrics", function(status, l) {
            if (id !== trackId) return
            // 404 means the track has no lyrics; anything else but 200 is retried on the next poll.
            if (status === 404) _fetchedFor = id
            if (!l) return
            _fetchedFor = id
            lines = parseLrc(l.subtitles)
        })
    }

    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.tidalRunning
        onTriggered: root.poll()
        onRunningChanged: if (!running) root.reset()
    }

    Timer {
        interval: 100; repeat: true
        running: root.playing && root.synced
        onTriggered: root.positionMs = root._syncedMs + (Date.now() - root._syncedAt)
    }
}
