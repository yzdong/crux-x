#!/usr/bin/env bash
# provision_controller.sh — controller bootstrap. Runs ON the VM.
#
# Installs OS deps, OpenClaw 2026.4.15, getnenai/openclaw-telemetry
# v0.1.0-postcrx, Python deps, and configures the
# systemd user service for the gateway. Idempotent — every step is
# guarded by an existence / version check.
#
# Invoked by provision_vm.sh; can also be run manually after a fresh
# git pull.

set -euo pipefail

LOG="/tmp/crux-land-provision.log"
exec > >(tee -a "$LOG") 2>&1

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log()  { printf '[%s][ctl] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s][ctl] WARN: %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s][ctl] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

REPO="${HOME}/crux-land"
OPENCLAW_VERSION="2026.4.15"
TELEMETRY_FORK="getnenai/openclaw-telemetry"
# Pinned to a specific commit on getnenai/openclaw-telemetry main.
# Stack of post-CRUX-Windows fixes layered on this SHA:
#   - svc-singleton + config-doc regression (was at 0757e53)
#   - browser-tool trace wrap (68521bd, replaced — used wrong CLI flags)
#   - browser-tool trace wrap with REAL CLI flags + .zip output
#     (5eb0eb8; closes "silent recording loss" failure mode)
#   - browserTrace declared in plugin configSchema (current HEAD
#     8621a1b; unblocks plugins.entries.telemetry.config.browserTrace.*
#     validation; closes preflight check 10)
# The fork has no tags yet, so we pin by SHA.
TELEMETRY_REF="ed9a805"
PY_VENV="${HOME}/crux-land-venv"

# 1. OS packages
log "apt update + base packages"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  build-essential curl git jq tmux \
  python3 python3-pip python3-venv \
  ca-certificates gnupg \
  unzip

# 2. gcloud SDK should already be present on GCE Debian; verify
if ! command -v gcloud >/dev/null 2>&1; then
  die "gcloud not on PATH on this VM (unexpected on a Debian GCE image)"
fi
if ! command -v gsutil >/dev/null 2>&1; then
  die "gsutil not on PATH (needed for archiving)"
fi

# 3. (Bitwarden CLI was here in earlier revisions; CRUX-Land uses GCP
# Secret Manager via gcloud, so no extra binary needed. The VM's
# cloud-platform service-account scope + the secretAccessor IAM
# binding give us read access without an unlock step.)

# 4. Node.js — OpenClaw 2026.4.15 requires Node v22.12+
NODE_REQUIRED_MAJOR=22
NEED_NODE=0
if ! command -v node >/dev/null 2>&1; then
  NEED_NODE=1
else
  current_major="$(node --version 2>/dev/null | sed -E 's/^v([0-9]+)\..*/\1/')"
  if [ -z "$current_major" ] || [ "$current_major" -lt "$NODE_REQUIRED_MAJOR" ]; then
    log "node v${current_major:-?} present but openclaw needs v${NODE_REQUIRED_MAJOR}+; reinstalling"
    NEED_NODE=1
  fi
fi
if [ "$NEED_NODE" -eq 1 ]; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_REQUIRED_MAJOR}.x" | sudo -E bash -
  sudo apt-get install -y -qq nodejs
fi
log "node $(node --version)"

# 5. OpenClaw at the pinned version
INSTALLED_OC_VERSION=""
if command -v openclaw >/dev/null 2>&1; then
  INSTALLED_OC_VERSION="$(openclaw --version 2>/dev/null | head -1 | awk '{print $NF}')"
fi
if [ "$INSTALLED_OC_VERSION" != "$OPENCLAW_VERSION" ]; then
  log "installing openclaw@${OPENCLAW_VERSION} (had: ${INSTALLED_OC_VERSION:-none})"
  sudo npm install -g "openclaw@${OPENCLAW_VERSION}"
fi
log "openclaw $(openclaw --version)"

# 6. getnenai/openclaw-telemetry — installed from GitHub, pinned by SHA.
# The plugin is loaded by OpenClaw at runtime via the path in
# openclaw.json; its only declared dep (`openclaw: workspace:*`) is a
# devDep that requires the openclaw monorepo as a parent workspace.
# Since we're loading it standalone, we skip `npm install` entirely —
# the plugin's index.ts is read directly by the OpenClaw runtime.
TELEMETRY_DIR="${HOME}/.openclaw/plugins/openclaw-telemetry"
if [ ! -d "$TELEMETRY_DIR" ] || ! (cd "$TELEMETRY_DIR" && git cat-file -e "${TELEMETRY_REF}^{commit}" 2>/dev/null); then
  log "cloning ${TELEMETRY_FORK} and checking out ${TELEMETRY_REF}"
  rm -rf "$TELEMETRY_DIR"
  git clone "https://github.com/${TELEMETRY_FORK}.git" "$TELEMETRY_DIR"
  (cd "$TELEMETRY_DIR" && git checkout "$TELEMETRY_REF")
fi

# 7. OpenClaw config + plugin install
#
# Schema reality (verified against `openclaw config schema` on
# 2026.4.15): there is NO top-level `tools.browser.trace.*` config
# block — `tools.*` accepts only profile/allow/deny/byProvider/web.
# Browser-trace config lives in this plugin's own block at
# `plugins.entries.telemetry.config.browserTrace.*`. The plugin reads
# it via `api.pluginConfig`. See openclaw-browser-research.md §3+§7.
#
# Plugin install: `plugins.entries.<id>.path` is also not in the
# schema. The right way to register a plugin path is `openclaw
# plugins install <dir> --link`, which writes plugins.load.paths and
# plugins.installs.<id> for us. Idempotent with --force.
OC_CONFIG="${HOME}/.openclaw/openclaw.json"
BROWSER_TRACES_DIR="${HOME}/.openclaw/logs/browser-traces"
TELEMETRY_LOG="${HOME}/.openclaw/logs/telemetry.jsonl"

mkdir -p "${HOME}/.openclaw/logs" "${HOME}/.openclaw/workspace" \
         "${HOME}/.openclaw/agents" "${HOME}/.openclaw/env" \
         "${BROWSER_TRACES_DIR}"
chmod 0700 "${BROWSER_TRACES_DIR}"  # contains parcel/listing data

# 7a. Ensure a base config file exists (empty object is valid).
if [ ! -f "$OC_CONFIG" ] || ! jq empty "$OC_CONFIG" 2>/dev/null; then
  log "writing minimal valid base config to ${OC_CONFIG}"
  echo '{}' > "$OC_CONFIG"
fi

# 7b. Register the plugin via the install CLI. `--force` is not
# supported with `--link`, so for idempotency we just swallow the
# "already installed" failure mode and verify with `plugins list` below.
log "registering telemetry plugin via 'openclaw plugins install --link'"
if ! openclaw plugins install "$TELEMETRY_DIR" --link >/tmp/plugin-install.log 2>&1; then
  if grep -qiE 'already|exists' /tmp/plugin-install.log; then
    log "  plugin already installed (idempotent re-run)"
  else
    cat /tmp/plugin-install.log >&2
    die "openclaw plugins install failed; see /tmp/plugin-install.log"
  fi
fi

# 7c. Merge our `plugins.entries.telemetry.{enabled, config}` block
# into the config file without clobbering plugins.installs /
# plugins.load.paths that the install command just wrote.
log "merging telemetry plugin config block"
jq \
  --arg log_path "$TELEMETRY_LOG" \
  --arg trace_dir "$BROWSER_TRACES_DIR" \
  '.plugins = (.plugins // {})
   | .plugins.entries = (.plugins.entries // {})
   | .plugins.entries.telemetry = {
       enabled: true,
       config: {
         enabled: true,
         filePath: $log_path,
         redact: { enabled: true }
       }
     }' "$OC_CONFIG" > "${OC_CONFIG}.new" && mv "${OC_CONFIG}.new" "$OC_CONFIG"

# 7d. Sanity-validate the merged config; fail fast if rejected.
if ! openclaw plugins list >/dev/null 2>&1; then
  warn "openclaw rejected the merged config; running 'openclaw doctor':"
  openclaw doctor 2>&1 | tail -20 >&2 || true
  die "openclaw config is invalid after merge — see ${OC_CONFIG}"
fi
log "openclaw config valid; telemetry plugin registered"

# 7a. Chromium is required by the browser tool's CDP backend. OpenClaw
# itself does NOT install one. Idempotency-guarded — apt install is a
# no-op if the package is already present at the right version.
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  log "installing chromium (browser-tool CDP target)"
  sudo apt-get install -y -qq chromium || sudo apt-get install -y -qq chromium-browser
fi
if command -v chromium >/dev/null 2>&1; then
  log "chromium $(chromium --version 2>/dev/null | head -1)"
elif command -v chromium-browser >/dev/null 2>&1; then
  log "chromium-browser $(chromium-browser --version 2>/dev/null | head -1)"
else
  warn "chromium not installed; tools.browser.trace will fail at first invocation."
fi

# 8. systemd user service for the gateway
SVC_DIR="${HOME}/.config/systemd/user"
mkdir -p "$SVC_DIR"
cat >"${SVC_DIR}/openclaw-gateway.service" <<UNIT
[Unit]
Description=OpenClaw Gateway (CRUX-Land)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/openclaw gateway start
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable openclaw-gateway.service
systemctl --user restart openclaw-gateway.service

# Linger so the service survives SSH disconnect (CRUX-Windows lesson)
if [ "$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)" != "yes" ]; then
  log "enabling linger for ${USER}"
  sudo loginctl enable-linger "$USER"
fi

# 9. Python venv + deps
if [ ! -d "$PY_VENV" ]; then
  log "creating venv at ${PY_VENV}"
  python3 -m venv "$PY_VENV"
fi
"$PY_VENV/bin/pip" install -q --upgrade pip
"$PY_VENV/bin/pip" install -q -r "${REPO}/experiments/land/scripts/requirements.txt"

# Symlink so helper scripts find a python that has the deps
mkdir -p "${HOME}/.local/bin"
ln -sf "$PY_VENV/bin/python3" "${HOME}/.local/bin/crux-land-python3"

# 10. Stage canonical workspace files
bash "${REPO}/experiments/land/scripts/stage-workspace.sh"

# 11. Touch ~/.crux-land/preflight.env if missing. Operator-specific
# infra actuals (PROJECT, BUCKET, ZONE, CONTROLLER_VM) come from the
# per-run manifest's "Resolved infra" section; if PROJECT/BUCKET are
# already in the operator's env (passed through SSH or set on the VM),
# we capture them here too.
ENV_FILE="${HOME}/.crux-land/preflight.env"
if [ ! -f "$ENV_FILE" ]; then
  mkdir -p "$(dirname "$ENV_FILE")"
  cat >"$ENV_FILE" <<EOF
# CRUX-Land preflight env. Populate from your per-run manifest's
# "Resolved infra" section before running preflight.sh.
# See experiments/land/scripts/preflight.env.example for the full schema.
PROJECT=${PROJECT:-}
BUCKET=${BUCKET:-}
ZONE=${ZONE:-us-central1-a}
CONTROLLER_VM=${CONTROLLER_VM:-crux-land-ctrl}
SINK_PHONE_NUMBER=
SINK_EMAIL_ADDRESS=
DEEPGRAM_API_KEY=
EOF
  chmod 600 "$ENV_FILE"
  warn "created ${ENV_FILE}; populate PROJECT/BUCKET (and others as needed) before running preflight"
fi

log "provision_controller.sh complete"
log "next steps:"
log "  1. operator: provision external accounts per USER-CHECKLIST.md"
log "  2. operator: ensure GSM secrets exist + are populated (see USER-CHECKLIST.md per-section gcloud commands)"
log "  3. operator: ensure channels.slack.{botToken,appToken} are populated in ~/.openclaw/openclaw.json (sourced from GSM slack-bot-token + slack-app-token)"
log "  4. operator: edit ${ENV_FILE} with sink phone, sink email, probe APN, deepgram key"
log "  5. bash ${REPO}/experiments/land/scripts/preflight.sh"
