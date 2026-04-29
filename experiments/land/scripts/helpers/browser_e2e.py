#!/usr/bin/env python3
"""browser_e2e.py — preflight helper for protocol §8 check 10.

**Plumbing-only check.** Verifies the browser-tool prerequisites are
all wired correctly, without triggering an agent turn (which would
need Anthropic API spend) and without invoking the browser CLI
directly (which bypasses the plugin hooks the recording wrap depends
on, so the test would always fail-negative).

Asserts:
  1. Chromium binary exists on PATH (or under common system paths).
  2. `openclaw browser status` returns `enabled: true` (the browser
     extension loaded its CLI sub-tree).
  3. The fork commit on disk at
     `~/.openclaw/plugins/openclaw-telemetry` matches the SHA pinned
     in `provision_controller.sh` (= the post-CRUX-Windows fork with
     the screenshot-path capture; defends against silent fork-drift).

The actual `tool.end` screenshotPath emission gets validated end-
to-end during dry-run smoke 1, where a real agent turn fires through
the gateway and the plugin hooks actually run.

Exits 0 on success, 1 on first failure with an actionable hint.

Usage:
  python3 browser_e2e.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


TELEMETRY_PLUGIN_DIR = Path.home() / ".openclaw" / "plugins" / "openclaw-telemetry"
EXPECTED_TELEMETRY_REF = "ed9a805"  # keep aligned with provision_controller.sh TELEMETRY_REF


def check_chromium() -> tuple[bool, str]:
    for cand in ("chromium", "chromium-browser", "google-chrome"):
        path = shutil.which(cand)
        if path:
            return True, f"{cand} -> {path}"
    return False, (
        "no chromium found on PATH (tried: chromium, chromium-browser, "
        "google-chrome). Install with: sudo apt-get install -y chromium"
    )


def check_browser_cli() -> tuple[bool, str]:
    res = subprocess.run(
        ["openclaw", "browser", "status"],
        capture_output=True, text=True, timeout=30,
    )
    if res.returncode != 0:
        return False, (
            f"`openclaw browser status` failed: rc={res.returncode}; "
            f"stderr={res.stderr.strip()[:200]}. The browser extension "
            "may not be loaded — check the gateway is up + the telemetry "
            "plugin loaded its dependencies."
        )
    if "enabled: true" not in res.stdout:
        return False, (
            "`openclaw browser status` ran but did not report enabled=true. "
            f"Output: {res.stdout.strip()[:300]}"
        )
    return True, "`openclaw browser status`: enabled=true"


def check_fork_pin() -> tuple[bool, str]:
    if not TELEMETRY_PLUGIN_DIR.is_dir():
        return False, f"telemetry plugin dir not present: {TELEMETRY_PLUGIN_DIR}"
    res = subprocess.run(
        ["git", "-C", str(TELEMETRY_PLUGIN_DIR), "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True, timeout=5,
    )
    if res.returncode != 0:
        return False, f"could not git-inspect {TELEMETRY_PLUGIN_DIR}: {res.stderr.strip()}"
    actual = res.stdout.strip()
    if actual != EXPECTED_TELEMETRY_REF:
        return False, (
            f"telemetry fork at {TELEMETRY_PLUGIN_DIR} is at SHA "
            f"{actual}, expected {EXPECTED_TELEMETRY_REF}. Run "
            "provision_controller.sh to re-pin."
        )
    return True, f"telemetry fork at SHA {actual}"


def main() -> int:
    checks = [
        ("chromium", check_chromium),
        ("browser CLI", check_browser_cli),
        ("fork pin", check_fork_pin),
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
        print(f"[browser] {name}: {hint}", file=sys.stderr)

    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
