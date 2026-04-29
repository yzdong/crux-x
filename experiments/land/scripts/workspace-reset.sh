#!/usr/bin/env bash
# workspace-reset.sh — restore the OpenClaw workspace to its t=0 state.
#
# Per protocol §8 "Workspace reset procedure". Run between dry runs and
# before the real run. Stops the gateway, archives current workspace
# state to GCS, removes agent-authored files, restores stock templates
# + canonical USER.md / HEARTBEAT.md, truncates telemetry, cleans
# ~/work/. Re-running preflight after this should produce 11/11 green.
#
# Usage:
#   bash workspace-reset.sh                  # interactive: prompts before destructive ops
#   bash workspace-reset.sh --confirm        # non-interactive

set -euo pipefail

CONFIRM=0
for arg in "$@"; do
  case "$arg" in
    --confirm) CONFIRM=1 ;;
  esac
done

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
info() { printf '[%s] %s\n' "$(ts)" "$*" >&2; }

REPO_DIR="${HOME}/crux-land"
AGENT_DIR="${REPO_DIR}/experiments/land/agent"
WORKSPACE_DIR="${HOME}/.openclaw/workspace"
LOGS_DIR="${HOME}/.openclaw/logs"
SESSIONS_DIR="${HOME}/.openclaw/agents/main/sessions"
TELEMETRY_LOG="${LOGS_DIR}/telemetry.jsonl"
WORK_DIR="${HOME}/work"
: "${BUCKET:?BUCKET not set; source ~/.crux-land/preflight.env first}"
GCS_BUCKET="gs://${BUCKET}"
STOCK_TEMPLATES_DIR="${OPENCLAW_TEMPLATES_DIR:-/usr/local/share/openclaw/templates}"

confirm() {
  if [ "$CONFIRM" -eq 1 ]; then return 0; fi
  printf '%s [y/N] ' "$1" >&2
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) info "aborted"; exit 1 ;; esac
}

# 1. Stop the gateway
info "stopping openclaw-gateway"
systemctl --user stop openclaw-gateway.service || true

# 2. Archive current workspace to GCS
ARCHIVE_TS="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
ARCHIVE_PATH="/tmp/workspace-${ARCHIVE_TS}.tgz"
info "archiving workspace + agents + logs to ${ARCHIVE_PATH}"
tar czf "$ARCHIVE_PATH" \
  -C "$HOME" \
  ".openclaw/workspace" \
  ".openclaw/agents" \
  ".openclaw/logs" 2>/dev/null || true

if command -v gsutil >/dev/null 2>&1; then
  GCS_TARGET="${GCS_BUCKET}/_dry-runs/${ARCHIVE_TS}/workspace.tgz"
  info "uploading to ${GCS_TARGET}"
  gsutil -q cp "$ARCHIVE_PATH" "$GCS_TARGET" || info "WARN: gsutil cp failed; archive remains at ${ARCHIVE_PATH}"
else
  info "WARN: gsutil missing; archive at ${ARCHIVE_PATH} not uploaded"
fi

# 3. Remove agent-authored workspace files
confirm "remove agent-authored files in ${WORKSPACE_DIR}/{memory,notes,drafts}?"
rm -rf "${WORKSPACE_DIR}/memory" \
       "${WORKSPACE_DIR}/notes" \
       "${WORKSPACE_DIR}/drafts" 2>/dev/null || true

# 4. Restore stock templates
if [ -d "$STOCK_TEMPLATES_DIR" ]; then
  info "restoring stock templates from ${STOCK_TEMPLATES_DIR}"
  for t in AGENTS.md SOUL.md IDENTITY.md BOOTSTRAP.md TOOLS.md; do
    if [ -r "${STOCK_TEMPLATES_DIR}/${t}" ]; then
      cp "${STOCK_TEMPLATES_DIR}/${t}" "${WORKSPACE_DIR}/${t}"
    fi
  done
else
  info "WARN: stock templates dir ${STOCK_TEMPLATES_DIR} not found; skipping (you may need to set OPENCLAW_TEMPLATES_DIR)"
fi

# 5. Stage canonical USER.md / HEARTBEAT.md from the experiment repo
info "staging canonical USER.md + HEARTBEAT.md from ${AGENT_DIR}"
cp "${AGENT_DIR}/USER.md" "${WORKSPACE_DIR}/USER.md"
cp "${AGENT_DIR}/HEARTBEAT.md" "${WORKSPACE_DIR}/HEARTBEAT.md"

# 6. Truncate telemetry
info "truncating ${TELEMETRY_LOG}"
mkdir -p "$LOGS_DIR"
: > "$TELEMETRY_LOG"

# 7. Clear ~/work/
confirm "remove all of ${WORK_DIR}?"
rm -rf "${WORK_DIR:?}/"* 2>/dev/null || true
mkdir -p "$WORK_DIR"

# 8. Restart gateway
info "starting openclaw-gateway"
systemctl --user start openclaw-gateway.service

info "workspace reset complete — re-run preflight.sh to confirm 11/11 green"
