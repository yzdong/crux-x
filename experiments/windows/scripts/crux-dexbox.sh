#!/usr/bin/env bash
# crux-dexbox: thin wrapper around the dexbox HTTP server for the Windows RDP target.
#
# Goes through the persistent dexbox server at localhost:8600 (not the `dexbox run`
# CLI) so every call shares one warm RDP session — otherwise Windows locks the
# session on each disconnect and subsequent screenshots capture LogonUI.
#
# Subcommands:
#   screenshot                          -> capture screenshot, save to /tmp/dexbox-shot-<ts>.png and print path
#   click X Y                           -> single left click at (X,Y)
#   type 'TEXT'                         -> type literal text
#   key 'KEY'                           -> press a key (e.g. Return, Tab, ctrl+s)
#
# Env overrides:
#   DEXBOX_TARGET  default win
#   DEXBOX_URL     default http://localhost:8600
#   DEXBOX_MODEL   default claude-sonnet-4-5-20250929

set -euo pipefail

DEXBOX_TARGET="${DEXBOX_TARGET:-win}"
DEXBOX_URL="${DEXBOX_URL:-http://localhost:8600}"
DEXBOX_MODEL="${DEXBOX_MODEL:-claude-sonnet-4-5-20250929}"
ACTIONS_URL="${DEXBOX_URL}/actions?model=${DEXBOX_MODEL}&desktop=${DEXBOX_TARGET}"

usage() {
  sed -n '2,18p' "$0"
}

# Bring the desktop up once per invocation; the server idempotently verifies
# an existing session and only cold-connects if none exists. This is cheap
# and avoids "desktop not connected" 502s on the first screenshot after a
# server restart.
ensure_up() {
  curl -fsS -X POST "${DEXBOX_URL}/desktops/${DEXBOX_TARGET}?action=up" >/dev/null
}

http_action() {
  local body="$1" accept="${2:-application/json}" out="${3:-}"
  if [[ -n "$out" ]]; then
    curl -fsS -X POST "$ACTIONS_URL" \
      -H "Accept: ${accept}" \
      -H "Content-Type: application/json" \
      -d "$body" -o "$out"
  else
    curl -fsS -X POST "$ACTIONS_URL" \
      -H "Accept: ${accept}" \
      -H "Content-Type: application/json" \
      -d "$body"
  fi
}

cmd="${1:-}"
shift || true

case "$cmd" in
  screenshot)
    ensure_up
    out="/tmp/dexbox-shot-$(date +%s%N).png"
    http_action '{"type":"computer_20250124","action":"screenshot"}' "image/png" "$out"
    if [[ ! -s "$out" ]] || ! head -c 8 "$out" | grep -q PNG; then
      echo "ERROR: screenshot output is not a PNG (saved at $out)" >&2
      exit 5
    fi
    echo "$out"
    ;;
  click)
    x="${1:?need X}"; y="${2:?need Y}"
    ensure_up
    http_action "$(printf '{"type":"computer_20250124","action":"left_click","coordinate":[%d,%d]}' "$x" "$y")"
    ;;
  type)
    text="${1:?need text}"
    ensure_up
    http_action "$(python3 -c 'import json,sys; print(json.dumps({"type":"computer_20250124","action":"type","text":sys.argv[1]}))' "$text")"
    ;;
  key)
    key="${1:?need key}"
    ensure_up
    http_action "$(python3 -c 'import json,sys; print(json.dumps({"type":"computer_20250124","action":"key","text":sys.argv[1]}))' "$key")"
    ;;
  -h|--help|"")
    usage; exit 0
    ;;
  *)
    echo "ERROR: unknown subcommand: $cmd" >&2
    usage; exit 2
    ;;
esac
