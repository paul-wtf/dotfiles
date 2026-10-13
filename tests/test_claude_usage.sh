#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh

script=../.config/quickshell/scripts/claude-usage.py
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

entry() {
    # entry <timestamp> <session> <message id> <model> <input> <output> <cache_create> <cache_read> [extra json]
    printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","requestId":"req_%s","message":{"id":"%s","model":"%s","usage":{"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d}}%s}\n' \
        "$1" "$2" "$3" "$3" "$4" "$5" "$6" "$7" "$8" "${9:-}"
}
prompt() {
    # prompt <timestamp> <session> <content json> [extra json]
    printf '{"type":"user","timestamp":"%s","sessionId":"%s","message":{"role":"user","content":%s}%s}\n' "$1" "$2" "$3" "${4:-}"
}

mkdir -p "$tmp/projects/-a/A/subagents" "$tmp/projects/-b"
{
    prompt 2026-10-13T11:00:00Z A '"hi"'
    prompt 2026-10-13T11:00:00Z A '[{"type":"tool_result","content":"ok"}]'
    prompt 2026-10-13T11:00:00Z A '"<command-name>/clear</command-name>"' ',"isMeta":true'
    entry  2026-10-13T11:00:00Z A msg_1 claude-opus-5-5 10 20 100 1000
    entry  2026-10-13T11:00:00Z A msg_1 claude-opus-5-5 10 20 100 1000
    entry  2026-10-13T02:00:00Z A msg_2 claude-opus-5-5 1 2 3 4
    echo 'not json'
} > "$tmp/projects/-a/A.jsonl"
{
    prompt 2026-10-10T12:00:00Z A '"subagent task"' ',"isSidechain":true'
    entry  2026-10-10T12:00:00Z A msg_3 claude-opus-5-5 5 5 0 0 ',"isSidechain":true'
} > "$tmp/projects/-a/A/subagents/agent-x.jsonl"
{
    prompt 2026-10-11T15:00:00Z B '"hello"'
    entry  2026-10-11T15:00:00Z B msg_5 claude-sonnet-5-5 0 0 0 5000
    entry  2026-10-01T12:00:00Z B msg_4 claude-opus-5-5 7 7 7 7
} > "$tmp/projects/-b/B.jsonl"

out="$(TZ=UTC CLAUDE_CONFIG_DIR="$tmp" CLAUDE_USAGE_NOW=2026-10-13T12:00:00Z python3 -I "$script" stats)"
get() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2], {}, {"d": d}))' "$out" "$1"; }
w() { get "d[\"windows\"][\"$1\"][\"$2\"]"; }

assert_eq "$(w 5h tokens)"       1130       "5h counts a response written twice once"
assert_eq "$(w 5h io)"           30         "5h in+out"
assert_eq "$(w 5h cache)"        1100       "5h cache sums creation and reads"
assert_eq "$(w 5h prompts)"      1          "tool results and meta lines are not prompts"
assert_eq "$(w 5h model)"        "Opus 5.5" "model names are shortened"
assert_eq "$(w 24h tokens)"      1140       "24h includes the 02:00 response"
assert_eq "$(w 7d tokens)"       6150       "7d includes subagents and drops entries older than a week"
assert_eq "$(w 7d prompts)"      2          "subagent prompts are not counted"
assert_eq "$(w 7d sessions)"     2          "subagent transcripts belong to their parent session"
assert_eq "$(w 7d active_days)"  3          "active days are distinct local dates"
assert_eq "$(w 7d peak_hour)"    15         "peak hour is the hour of day with most tokens"
assert_eq "$(w 7d model)"        "Sonnet 5.5" "preferred model is the one with most tokens"
assert_eq "$(get 'd["heatmap"]["days"]')" "['Mi', 'Do', 'Fr', 'Sa', 'So', 'Mo', 'Di']" "heatmap rows run from six days ago to today"
assert_eq "$(get 'd["heatmap"]["cells"][6][11]')" 1130 "heatmap cell holds tokens per hour"
assert_eq "$(get 'd["heatmap"]["cells"][4][15]')" 5000 "heatmap rows follow the calendar day"
assert_eq "$(get 'sum(map(sum, d["heatmap"]["cells"]))')" 6150 "heatmap total matches the 7d window"

cat > "$tmp/response.json" <<'EOF'
{"five_hour":{"utilization":37.0},"limits":[
 {"kind":"session","group":"session","percent":37,"severity":"normal","resets_at":"2026-10-13T21:40:00+00:00","scope":null},
 {"kind":"weekly_all","group":"weekly","percent":70,"severity":"warning","resets_at":"2026-10-15T09:00:00+00:00","scope":null},
 {"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal","resets_at":"2026-10-15T09:00:00+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}
]}
EOF
out="$(python3 -I "$script" limits --response "$tmp/response.json")"

assert_eq "$(get 'd["ok"]')"                          True       "a valid response is ok"
assert_eq "$(get '[l["label"] for l in d["limits"]]')" "['Session', 'Woche', 'Woche Fable']" "limits are labelled by kind and scope"
assert_eq "$(get 'd["limits"][1]["severity"]')"        warning    "severity is passed through"
assert_eq "$(get 'd["limits"][0]["resets_at"]')"       1791927600 "reset time becomes a unix timestamp"

echo '{"error":{"type":"authentication_error"}}' > "$tmp/expired.json"
out="$(python3 -I "$script" limits --response "$tmp/expired.json")"
assert_eq "$(get 'd["ok"]')" False "an error response is not ok"

finish
