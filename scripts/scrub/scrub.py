#!/usr/bin/env python3
"""Pre-commit scrub for the crux-x repo.

Sends `git diff --cached` to Claude Haiku 4.5 with the prompt at
`scripts/scrub/SCRUB_PROMPT.md` and blocks the commit if any finding is
severity `critical` or `high`. Fails open on infra failures (API down,
JSON parse error) so a network glitch never blocks legitimate work.

Usage:
    python3 scripts/scrub/scrub.py                    # normal pre-commit run
    python3 scripts/scrub/scrub.py --diff-file PATH   # test with a fixture diff
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PROMPT_PATH = REPO_ROOT / "scripts/scrub/SCRUB_PROMPT.md"
MODEL = "claude-haiku-4-5"


def get_staged_diff() -> str:
    return subprocess.run(
        ["git", "diff", "--cached", "--no-color"],
        capture_output=True, text=True, check=True,
    ).stdout


def parse_response(raw: str) -> dict:
    """Extract the JSON object from the model response.

    The prompt asks for JSON-only output. Be defensive against
    occasional markdown-fence wrapping.
    """
    raw = raw.strip()
    fenced = re.match(r"^```(?:json)?\s*(.*?)\s*```$", raw, re.DOTALL)
    if fenced:
        raw = fenced.group(1).strip()
    return json.loads(raw)


def call_haiku(prompt: str, diff: str) -> dict:
    import anthropic
    client = anthropic.Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=4096,
        system=prompt,
        messages=[{
            "role": "user",
            "content": f"Scan this `git diff --cached` and respond with JSON only:\n\n```\n{diff}\n```",
        }],
    )
    return parse_response(response.content[0].text)


def print_findings(findings: list[dict]) -> None:
    for f in findings:
        sev = f.get("severity", "?").upper()
        print(f"\n[{sev}] {f.get('file', '?')}:{f.get('line', '?')}")
        print(f"  category: {f.get('category', '?')}")
        print(f"  content:  {f.get('content', '?')}")
        print(f"  fix:      {f.get('suggested_fix', '?')}")
        print(f"  reason:   {f.get('reasoning', '?')}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--diff-file",
        type=Path,
        help="Read the diff from a file instead of `git diff --cached` (for testing)",
    )
    args = parser.parse_args()

    if args.diff_file:
        diff = args.diff_file.read_text()
    else:
        diff = get_staged_diff()

    if not diff.strip():
        print("scrub: no staged changes; nothing to scan")
        return 0

    prompt = PROMPT_PATH.read_text()

    try:
        result = call_haiku(prompt, diff)
    except Exception as e:
        # Fail open: warn but allow. A scrub infra failure shouldn't block
        # legitimate commits. Repeated failures will surface in commit logs.
        print(f"scrub: WARNING — could not run scan ({e}); allowing commit", file=sys.stderr)
        return 0

    findings = result.get("findings", [])

    if not findings:
        print("scrub: clean")
        return 0

    print_findings(findings)

    blocking = [f for f in findings if f.get("severity") in ("critical", "high")]
    if blocking:
        print(f"\nscrub: BLOCKED — {len(blocking)} critical/high finding(s)")
        print("Resolve the flagged content, re-stage, and retry.")
        print("If a finding is a false positive, update the allowlist in")
        print(f"{PROMPT_PATH.relative_to(REPO_ROOT)} and commit that change first.")
        return 1

    print(f"\nscrub: passed with {len(findings)} non-blocking finding(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
