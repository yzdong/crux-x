#!/usr/bin/env python3
"""telemetry_e2e.py — preflight helper for protocol §8 check 8.

**Plumbing-only check.** Verifies the telemetry pipeline is wired
correctly without triggering a real agent turn (which would require
Anthropic API keys + spend a few cents per preflight run).

Asserts:
  1. `openclaw plugins list` reports `telemetry` with status=loaded.
  2. The configured telemetry log path's parent directory is writable
     by the running user.

The actual `tool.start` / `tool.end` / `agent.usage` event emission
gets validated end-to-end during dry-run smoke 1, which fires a real
agent turn through the gateway. By that point we've already spent
the preflight budget on the cheaper checks.

Exits 0 on success, 1 on any failure with an actionable hint.

Usage:
  python3 telemetry_e2e.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


CONFIG_PATH = Path.home() / ".openclaw" / "openclaw.json"
DEFAULT_LOG_PATH = Path.home() / ".openclaw" / "logs" / "telemetry.jsonl"


def check_plugin_loaded() -> tuple[bool, str]:
    # 60s timeout — openclaw plugins list opens a WS connection to the
    # gateway and waits for plugin enumeration; can take 20-30s on a
    # cold gateway.
    res = subprocess.run(
        ["openclaw", "plugins", "list"],
        capture_output=True, text=True, timeout=60,
    )
    if res.returncode != 0:
        return False, f"`openclaw plugins list` failed: rc={res.returncode}; stderr={res.stderr.strip()[:200]}"
    out = res.stdout
    # Match a row containing "telemetr" + "loaded" — table can wrap "telemetry"
    # across visual lines.
    for line in out.splitlines():
        low = line.lower()
        if "telemetr" in low and "loaded" in low:
            return True, "telemetry plugin loaded"
    return False, (
        "telemetry plugin not in `loaded` state. Re-run "
        "`openclaw plugins install <fork-dir> --link` and restart "
        "the gateway."
    )


def check_log_writable() -> tuple[bool, str]:
    if not CONFIG_PATH.exists():
        return False, f"{CONFIG_PATH} not found"
    try:
        cfg = json.loads(CONFIG_PATH.read_text())
    except Exception as e:
        return False, f"could not parse {CONFIG_PATH}: {e}"
    log_path = (
        cfg.get("plugins", {}).get("entries", {})
           .get("telemetry", {}).get("config", {})
           .get("filePath")
    )
    if not log_path:
        log_path = str(DEFAULT_LOG_PATH)
    parent = Path(log_path).expanduser().parent
    if not parent.is_dir():
        return False, f"telemetry log parent dir does not exist: {parent}"
    if not os.access(parent, os.W_OK):
        return False, f"telemetry log parent dir not writable: {parent}"
    return True, f"log dir writable: {parent}"


def main() -> int:
    checks = [
        ("plugin loaded", check_plugin_loaded),
        ("log writable", check_log_writable),
    ]
    for name, fn in checks:
        try:
            ok, hint = fn()
        except Exception as e:
            print(f"ERROR: {name}: unexpected failure: {e}", file=sys.stderr)
            return 1
        if not ok:
            print(f"ERROR: {name}: {hint}", file=sys.stderr)
            return 1
        print(f"[telemetry] {name}: {hint}", file=sys.stderr)

    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
