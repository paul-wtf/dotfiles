#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./helpers.sh

script=../.config/quickshell/scripts/claude-usage.py
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

entry() {
    # entry <timestamp> <message id> <request id> <input> <output> <cache_create> <cache_read>
    printf '{"type":"assistant","timestamp":"%s","requestId":"%s","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d}}}\n' \
        "$1" "$3" "$2" "$4" "$5" "$6" "$7"
}

mkdir -p "$tmp/projects/-a/session/subagents" "$tmp/projects/-b"
{
    entry 2026-10-13T11:00:00Z msg_1 req_1 10 20 100 1000
    entry 2026-10-13T11:00:00Z msg_1 req_1 10 20 100 1000
    entry 2026-10-13T02:00:00Z msg_2 req_2 1 2 3 4
    echo '{"type":"user","timestamp":"2026-10-13T11:00:00Z","message":{"content":"hi"}}'
    echo 'not json'
} > "$tmp/projects/-a/s1.jsonl"
entry 2026-10-10T12:00:00Z msg_3 req_3 5 5 0 0 > "$tmp/projects/-a/session/subagents/agent-x.jsonl"
entry 2026-10-01T12:00:00Z msg_4 req_4 7 7 7 7 > "$tmp/projects/-b/old.jsonl"

out="$(CLAUDE_CONFIG_DIR="$tmp" CLAUDE_USAGE_NOW=2026-10-13T12:00:00Z python3 -I "$script" tokens)"
get() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2], {}, {"d": d}))' "$out" "$1"; }

assert_eq "$(get 'd["tokens"]["5h"]["io"]')"     30   "5h in+out counts a duplicated message once"
assert_eq "$(get 'd["tokens"]["5h"]["cache"]')"  1100 "5h cache sums creation and reads"
assert_eq "$(get 'd["tokens"]["24h"]["io"]')"    33   "24h includes the 02:00 message"
assert_eq "$(get 'd["tokens"]["7d"]["io"]')"     43   "7d includes subagent transcripts"
assert_eq "$(get 'd["tokens"]["7d"]["cache"]')"  1107 "7d excludes entries older than a week"

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
