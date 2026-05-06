#!/bin/bash
# Install the scrub pre-commit hook for this repo.
#
# Run once after cloning: `bash scripts/scrub/install-hook.sh`

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_PATH="$REPO_ROOT/.git/hooks/pre-commit"

cat > "$HOOK_PATH" <<'EOF'
#!/bin/bash
# Auto-installed by scripts/scrub/install-hook.sh — runs LLM-based scrub
# on staged content. Fails open on infra issues. Bypass with --no-verify.
exec python3 "$(git rev-parse --show-toplevel)/scripts/scrub/scrub.py"
EOF

chmod +x "$HOOK_PATH"

echo "Installed pre-commit hook → $HOOK_PATH"
echo "Test it: bash scripts/scrub/test-scrub.sh"
echo "Bypass once: git commit --no-verify"
