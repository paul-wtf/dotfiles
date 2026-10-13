#!/usr/bin/env python3
"""Claude usage for the bar, one JSON line per call.

  claude-usage.py tokens                  tokens from local transcripts
  claude-usage.py limits [--response F]   plan limits from the usage endpoint
"""
import json, os, sys, time, urllib.error, urllib.request
from datetime import datetime
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
WINDOWS = {"5h": 5 * 3600, "24h": 24 * 3600, "7d": 7 * 86400}
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"


def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def now():
    s = os.environ.get("CLAUDE_USAGE_NOW")
    return parse_ts(s) if s else time.time()


def tokens():
    t_now = now()
    oldest = t_now - max(WINDOWS.values())
    seen = {}
    for path in (CONFIG_DIR / "projects").rglob("*.jsonl"):
        try:
            if path.stat().st_mtime < oldest:
                continue
            with open(path, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if '"usage"' not in line:
                        continue
                    try:
                        e = json.loads(line)
                        msg = e["message"]
                        usage = msg["usage"]
                        ts = parse_ts(e["timestamp"])
                    except (ValueError, KeyError, TypeError):
                        continue
                    if ts < oldest:
                        continue
                    # One API response is written once per content block, each
                    # line carrying the same usage.
                    seen[(msg.get("id"), e.get("requestId"))] = (ts, usage)
        except OSError:
            continue

    out = {w: {"io": 0, "cache": 0} for w in WINDOWS}
    for ts, u in seen.values():
        io = (u.get("input_tokens") or 0) + (u.get("output_tokens") or 0)
        cache = (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0)
        for w, span in WINDOWS.items():
            if ts >= t_now - span:
                out[w]["io"] += io
                out[w]["cache"] += cache
    return {"tokens": out}


def label(limit):
    base = {"session": "Session", "weekly_all": "Woche", "weekly_scoped": "Woche"}.get(
        limit.get("kind"), limit.get("kind", "?"))
    model = ((limit.get("scope") or {}).get("model") or {}).get("display_name")
    return f"{base} {model}" if model else base


def fetch():
    # Read-only: refreshing here would rotate the refresh token and sign the CLI out.
    creds = json.loads((CONFIG_DIR / ".credentials.json").read_text())
    req = urllib.request.Request(USAGE_URL, headers={
        "Authorization": "Bearer " + creds["claudeAiOauth"]["accessToken"],
        "anthropic-beta": "oauth-2025-04-20",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": {"type": f"http_{e.code}"}}


def limits(response_file=None):
    try:
        data = json.loads(Path(response_file).read_text()) if response_file else fetch()
    except Exception as e:
        return {"ok": False, "error": type(e).__name__}
    if "limits" not in data:
        return {"ok": False, "error": (data.get("error") or {}).get("type", "no limits")}
    return {"ok": True, "fetched_at": int(now()), "limits": [{
        "label": label(l),
        "percent": l.get("percent") or 0,
        "severity": l.get("severity") or "normal",
        "resets_at": int(parse_ts(l["resets_at"])) if l.get("resets_at") else 0,
    } for l in data["limits"]]}


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "tokens":
        result = tokens()
    elif mode == "limits":
        result = limits(sys.argv[3] if sys.argv[2:3] == ["--response"] else None)
    else:
        sys.exit(__doc__)
    print(json.dumps(result), flush=True)
