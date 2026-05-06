#!/usr/bin/env python3
"""Claude Code PreToolUse hook wrapper for the scrub.

Reads the tool call JSON from stdin (Claude Code hook contract). If the
tool call is a Bash invocation that contains `git commit`, runs the
scrub script and propagates the result to Claude:

- exit 0   → scrub passed; allow the tool call.
- exit 2   → scrub blocked; surfaces to Claude so it can self-correct
             before attempting the commit.

Non-`git commit` invocations exit 0 silently (the hook is no-op).
"""

import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRUB_PATH = REPO_ROOT / "scripts/scrub/scrub.py"


def main() -> int:
    try:
        tool_call = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Malformed input — fail open.
        return 0

    tool_input = tool_call.get("tool_input", {})
    command = tool_input.get("command", "") or ""

    # Only trigger on `git commit` (not on `git status`, `git diff`, etc.)
    # `git commit --amend` and `git commit --no-verify` both still hit
    # this hook and still need scanning.
    if not re.search(r"\bgit\s+commit\b", command):
        return 0

    result = subprocess.run(
        ["python3", str(SCRUB_PATH)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )

    # Surface scrub stdout/stderr to Claude via stderr so the contents
    # appear in the tool-call result.
    if result.stdout:
        print(result.stdout, file=sys.stderr)
    if result.stderr:
        print(result.stderr, file=sys.stderr)

    if result.returncode == 1:
        print(
            "\nclaude-hook: blocked by scrub. Resolve the flagged content "
            "before retrying the commit, or update SCRUB_PROMPT.md if it's "
            "a false positive.",
            file=sys.stderr,
        )
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
