#!/usr/bin/env bash
# stage-workspace.sh — copy the canonical USER.md + HEARTBEAT.md from
# the experiment repo into the OpenClaw workspace. Use when you only
# need to refresh those two files (e.g. after editing them in the repo
# and pulling). For a full reset, use workspace-reset.sh instead.

set -euo pipefail

REPO_DIR="${HOME}/crux-land"
AGENT_DIR="${REPO_DIR}/experiments/land/agent"
WORKSPACE_DIR="${HOME}/.openclaw/workspace"

if [ ! -r "${AGENT_DIR}/USER.md" ] || [ ! -r "${AGENT_DIR}/HEARTBEAT.md" ]; then
  echo "ERROR: ${AGENT_DIR} is missing canonical files. Pull the latest from the repo." >&2
  exit 1
fi

mkdir -p "$WORKSPACE_DIR"

cp "${AGENT_DIR}/USER.md" "${WORKSPACE_DIR}/USER.md"
cp "${AGENT_DIR}/HEARTBEAT.md" "${WORKSPACE_DIR}/HEARTBEAT.md"

USER_HASH="$(sha256sum "${WORKSPACE_DIR}/USER.md" | awk '{print $1}')"
HEART_HASH="$(sha256sum "${WORKSPACE_DIR}/HEARTBEAT.md" | awk '{print $1}')"

cat <<EOF
staged USER.md (sha256: ${USER_HASH})
staged HEARTBEAT.md (sha256: ${HEART_HASH})

if this is a kickoff, paste both hashes into runs/<run-id>/manifest.md
under "Scaffold + workspace at t=0".
EOF
