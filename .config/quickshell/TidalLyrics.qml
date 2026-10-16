pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Lyrics of the current Tidal track. Syllable timings come from the API behind the Radiant
// Lyrics plugin; Tidal's own line-timed lyrics (via TidaLuna TidalAPI) are the fallback.
Singleton {
    id: root

    readonly property string api: "http://127.0.0.1:24123"
    readonly property string rlApi: "https://api.atomix.one/rl-api"
    readonly property string rlFallback: "https://rl-api.kineticsand.net/lyrics"
    // Published in plain text in meowarex/TidalLuna-Plugins (radiant-lyrics-luna/src/api.ts).
    readonly property var rlHeaders: ({ "P-Access-Token-Id": "58hy4s86", "P-Access-Token": "xjehy2lfg5h5mjwotoxrcqugam" })

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

    property real _syncedMs: 0
    property real _syncedAt: 0
    property string _fetchedFor: ""

    function isTidal(player) {
        return !!player && (player.identity ?? "").toLowerCase().includes("tidal")
    }

    function isActive(syllable) {
        return positionMs >= syllable.time && positionMs < syllable.end
    }

    // Groups a line's syllables into words; a syllable ending in whitespace closes its word.
    function wordsOf(line) {
        var words = [], current = null
        var syllables = line.syllables || []
        for (var i = 0; i < syllables.length; i++) {
            var s = syllables[i]
            if (!current || current.bg !== s.bg) {
                current = { bg: s.bg, syllables: [] }
                words.push(current)
            }
            current.syllables.push({ text: s.text.trim(), time: s.time, end: s.end })
            if (/\s$/.test(s.text)) current = null
        }
        return words.filter(w => w.syllables.some(s => s.text.length > 0))
    }

    function escapeHtml(t) {
        return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function styledLine(line, index, accent) {
        if (line.text.length === 0) return "♪"
        if (index !== currentIndex || !line.syllables || line.syllables.length === 0) return escapeHtml(line.text)
        var out = ""
        for (var i = 0; i < line.syllables.length; i++) {
            var s = line.syllables[i]
            out += isActive(s)
                ? "<b><font color=\"" + accent + "\">" + escapeHtml(s.text) + "</font></b>"
                : escapeHtml(s.text)
        }
        return out
    }

    function parseLrc(text) {
        var out = []
        var rows = (text || "").split("\n")
        for (var i = 0; i < rows.length; i++) {
            var m = /^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$/.exec(rows[i])
            if (m) out.push({ time: (parseInt(m[1]) * 60 + parseFloat(m[2])) * 1000, text: m[3].trim(), syllables: [] })
        }
        return out
    }

    function parseRl(body) {
        return body.data.map(function(l) {
            var syllables = (l.syllabus || []).map(s => ({
                text: s.text, time: s.time, end: s.time + s.duration, bg: !!s.isBackground
            }))
            // Close tiny gaps to the next syllable of the same voice so the highlight doesn't blink.
            for (var i = 0; i < syllables.length; i++)
                for (var j = i + 1; j < syllables.length; j++)
                    if (syllables[j].bg === syllables[i].bg) {
                        if (syllables[j].time - syllables[i].end < 250)
                            syllables[i].end = Math.max(syllables[i].end, syllables[j].time)
                        break
                    }
            return { time: l.startTime * 1000, text: l.text, syllables: syllables }
        })
    }

    function request(url, headers, done) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var body = null
            if (xhr.status === 200) {
                try { body = JSON.parse(xhr.responseText) } catch (e) {}
            }
            done(xhr.status, body)
        }
        xhr.open("GET", url)
        for (var h in headers || {}) xhr.setRequestHeader(h, headers[h])
        xhr.send()
    }

    function reset() {
        trackId = ""
        lines = []
        playing = false
        _fetchedFor = ""
    }

    function poll() {
        request(api + "/player", null, function(status, p) {
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
            if (id && _fetchedFor !== id) {
                _fetchedFor = id
                fetchLyrics(id, p.item)
            }
        })
    }

    function fetchLyrics(id, item) {
        var artist = item.artists && item.artists.length > 0 ? item.artists[0].name : ""
        var q = "?title=" + encodeURIComponent(item.name || "") + "&artist=" + encodeURIComponent(artist)
        if (item.isrc) q += "&isrc=" + encodeURIComponent(item.isrc)
        q += "&platform=rl"

        var useRl = function(body) {
            if (id !== trackId) return true
            if (!body || !Array.isArray(body.data) || (body.type !== "Word" && body.type !== "Line")) return false
            var parsed = parseRl(body)
            if (parsed.length === 0) return false
            lines = parsed
            return true
        }
        var useTidal = function() {
            request(api + "/tracks/" + id + "/lyrics", null, function(status, l) {
                if (id === trackId && l) lines = parseLrc(l.subtitles)
            })
        }

        request(rlApi + q, rlHeaders, function(status, body) {
            if (useRl(body)) return
            // 404 from the primary means the service has no lyrics for this track at all.
            if (status === 404) { useTidal(); return }
            request(rlFallback + q, null, function(status2, body2) {
                if (!useRl(body2)) useTidal()
            })
        })
    }

    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.tidalRunning
        onTriggered: root.poll()
        onRunningChanged: if (!running) root.reset()
    }

    Timer {
        interval: 50; repeat: true
        running: root.playing && root.synced
        onTriggered: root.positionMs = root._syncedMs + (Date.now() - root._syncedAt)
    }
}
