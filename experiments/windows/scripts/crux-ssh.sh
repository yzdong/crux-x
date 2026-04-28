#!/usr/bin/env bash
# crux-ssh: run a PowerShell command on the Windows target VM.
#
# Reads creds from ~/.dexbox/shared/creds.json (windows_admin_password).
# Output: PowerShell stdout+stderr, exit code from PowerShell.
#
# Usage:
#   crux-ssh '<powershell command>'
#   echo '<powershell command>' | crux-ssh -
#
# Env overrides:
#   CRUX_WIN_HOST  default <windows-vm-ip>
#   CRUX_WIN_USER  default dexbox

set -uo pipefail

WIN_HOST="${CRUX_WIN_HOST:-<windows-vm-ip>}"
WIN_USER="${CRUX_WIN_USER:-dexbox}"
CREDS_FILE="${CREDS_FILE:-$HOME/.dexbox/shared/creds.json}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,15p' "$0"
  exit 0
fi

# Read PS command from arg or stdin
if [[ "${1:-}" == "-" ]]; then
  PS_CMD="$(cat)"
elif [[ $# -ge 1 ]]; then
  PS_CMD="$*"
else
  echo "ERROR: no PowerShell command supplied" >&2
  exit 2
fi

if [[ ! -f "$CREDS_FILE" ]]; then
  echo "ERROR: creds file not found: $CREDS_FILE" >&2
  exit 3
fi

WIN_PASS="$(python3 -c "import json,sys; print(json.load(open('$CREDS_FILE'))['windows_admin_password'])" 2>/dev/null)"
if [[ -z "${WIN_PASS:-}" ]]; then
  echo "ERROR: failed to read windows_admin_password from $CREDS_FILE" >&2
  exit 4
fi

# We pass the PS command via -EncodedCommand to avoid quoting hell. PS expects UTF-16LE base64.
ENCODED="$(python3 -c "import sys,base64; print(base64.b64encode(sys.argv[1].encode('utf-16-le')).decode())" "$PS_CMD")"

exec sshpass -p "$WIN_PASS" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  -o ConnectTimeout=20 \
  "${WIN_USER}@${WIN_HOST}" \
  "powershell -NoProfile -EncodedCommand $ENCODED"
