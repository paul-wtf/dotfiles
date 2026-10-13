#!/usr/bin/env python3
"""Claude usage for the bar, one JSON line per call.

  claude-usage.py stats                   activity from local transcripts
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


WEEKDAYS = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]


def model_name(model_id):
    # claude-opus-5-5 -> Opus 5.5
    parts = model_id.removeprefix("claude-").split("-")
    return parts[0].capitalize() + (" " + ".".join(parts[1:]) if parts[1:] else "")


def is_prompt(e):
    if e.get("isMeta") or e.get("isSidechain"):
        return False
    content = (e.get("message") or {}).get("content")
    if isinstance(content, list):
        return not any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)
    return isinstance(content, str)


def read_entries(oldest):
    responses, prompts, activity = {}, [], []
    for path in (CONFIG_DIR / "projects").rglob("*.jsonl"):
        subagent = "subagents" in path.parts
        try:
            if path.stat().st_mtime < oldest:
                continue
            with open(path, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if '"type":"user"' not in line and '"usage"' not in line:
                        continue
                    try:
                        e = json.loads(line)
                        ts = parse_ts(e["timestamp"])
                    except (ValueError, KeyError, TypeError):
                        continue
                    if ts < oldest or e.get("type") not in ("user", "assistant"):
                        continue
                    activity.append((ts, None if subagent else e.get("sessionId")))
                    msg = e.get("message") or {}
                    if e["type"] == "user":
                        if not subagent and is_prompt(e):
                            prompts.append(ts)
                    elif msg.get("usage") and msg.get("model") != "<synthetic>":
                        # One API response is written once per content block, each
                        # line carrying the same usage.
                        responses[(msg.get("id"), e.get("requestId"))] = (ts, msg.get("model"), msg["usage"])
        except OSError:
            continue
    return list(responses.values()), prompts, activity


def stats():
    t_now = now()
    oldest = t_now - max(WINDOWS.values())
    responses, prompts, activity = read_entries(oldest)

    windows = {}
    for w, span in WINDOWS.items():
        since = t_now - span
        io = cache = 0
        by_model, by_hour = {}, {}
        for ts, model, u in responses:
            if ts < since:
                continue
            r_io = (u.get("input_tokens") or 0) + (u.get("output_tokens") or 0)
            r_cache = (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0)
            io += r_io
            cache += r_cache
            by_model[model] = by_model.get(model, 0) + r_io + r_cache
            hour = time.localtime(ts).tm_hour
            by_hour[hour] = by_hour.get(hour, 0) + r_io + r_cache
        recent = [(ts, sid) for ts, sid in activity if ts >= since]
        windows[w] = {
            "tokens": io + cache,
            "io": io,
            "cache": cache,
            "prompts": sum(1 for ts in prompts if ts >= since),
            "sessions": len({sid for _, sid in recent if sid}),
            "active_days": len({time.strftime("%F", time.localtime(ts)) for ts, _ in recent}),
            "peak_hour": max(by_hour, key=by_hour.get) if by_hour else None,
            "model": model_name(max(by_model, key=by_model.get)) if by_model else None,
        }

    today = time.localtime(t_now)
    midnight = time.mktime((today.tm_year, today.tm_mon, today.tm_mday, 0, 0, 0, 0, 0, -1))
    days = [time.localtime(midnight - d * 86400 + 43200) for d in range(6, -1, -1)]
    dates = [time.strftime("%F", d) for d in days]
    cells = [[0] * 24 for _ in days]
    for ts, _, u in responses:
        lt = time.localtime(ts)
        date = time.strftime("%F", lt)
        if date in dates:
            cells[dates.index(date)][lt.tm_hour] += sum(u.get(k) or 0 for k in (
                "input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    heatmap = {"days": [WEEKDAYS[d.tm_wday] for d in days], "cells": cells}

    return {"windows": windows, "heatmap": heatmap}


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
    if mode == "stats":
        result = stats()
    elif mode == "limits":
        result = limits(sys.argv[3] if sys.argv[2:3] == ["--response"] else None)
    else:
        sys.exit(__doc__)
    print(json.dumps(result), flush=True)
