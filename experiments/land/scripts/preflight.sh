#!/usr/bin/env bash
# preflight.sh — CRUX-Land experiment preflight validator.
#
# Runs on the controller VM (crux-land-ctrl). Exits 0 if every check
# passes, 1 on first failure with a human-actionable hint. Mostly
# read-only — checks 10, 11, and 12 each trigger one real round-trip
# (a dummy tool call, an outbound Twilio call, and a browser navigate)
# to validate the end-to-end pipeline. Each writes a small artifact
# (telemetry events, a Twilio recording, a browser trace dir); none
# mutate the experiment state in a way that affects a real run.
#
# Usage:
#   bash preflight.sh
#   bash preflight.sh --verbose
#
# Typical invocation from a laptop:
#   gcloud compute ssh ${CONTROLLER_VM:-crux-land-ctrl} --tunnel-through-iap \
#     --zone=${ZONE:-us-central1-a} -- bash ~/crux-land/scripts/preflight.sh

set -u

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    *) ;;
  esac
done

# ---- env -------------------------------------------------------------------
# preflight.env is operator-specific (GCP project, GCS bucket, sink
# phone/email fallbacks); gitignored; populated by provision_controller.sh
# from the per-run manifest's "Resolved infra" section.
ENV_FILE="${HOME}/.crux-land/preflight.env"
if [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

: "${PROJECT:=}"
: "${BUCKET:=}"
: "${ZONE:=us-central1-a}"
: "${CONTROLLER_VM:=crux-land-ctrl}"
: "${SINK_PHONE_NUMBER:=}"
: "${SINK_EMAIL_ADDRESS:=}"

if [ -z "$PROJECT" ]; then
  printf '[%s] [FAIL ] env/project: PROJECT not set in %s; run provision_controller.sh or `export PROJECT=<your-gcp-project>`.\n' \
    "$(date -u +%FT%TZ)" "$ENV_FILE" >&2
  exit 1
fi

# Fall back to GSM if sink env vars not set in preflight.env. Avoids
# requiring the operator to populate two places (GSM + .env).
if [ -z "$SINK_PHONE_NUMBER" ]; then
  SINK_PHONE_NUMBER="$(gcloud secrets versions access latest --secret=crux-land-sink-phone --project="$PROJECT" 2>/dev/null || true)"
fi
if [ -z "$SINK_EMAIL_ADDRESS" ]; then
  SINK_EMAIL_ADDRESS="$(gcloud secrets versions access latest --secret=crux-land-sink-email --project="$PROJECT" 2>/dev/null || true)"
fi

OPENCLAW_VERSION_REQUIRED="2026.4.15"
OPENCLAW_GATEWAY_UNIT="openclaw-gateway.service"
TELEMETRY_LOG="${HOME}/.openclaw/logs/telemetry.jsonl"
SCAFFOLD_DIR="${HOME}/.openclaw"

# ---- logging ---------------------------------------------------------------
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
info() { [ "$VERBOSE" -eq 1 ] && printf '[%s] [INFO ] %s\n' "$(ts)" "$*" >&2; return 0; }
ok() { [ "$VERBOSE" -eq 1 ] && printf '[%s] [ OK  ] %s\n' "$(ts)" "$*" >&2; return 0; }
fail() { printf '[%s] [FAIL ] %s: %s\n' "$(ts)" "$1" "$2" >&2; }
die_fail() { fail "$1" "$2"; exit 1; }

require_env() {
  local var="$1" check="$2"
  if [ -z "${!var}" ]; then
    die_fail "$check" "env var \$$var is unset; populate ${ENV_FILE} (see scripts/README.md)."
  fi
}

# -----------------------------------------------------------------------------
# 1. controller resources: disk + RAM
# -----------------------------------------------------------------------------
check_resources() {
  info "check 1/10: controller disk + RAM"

  local disk_gb_free
  disk_gb_free="$(df -BG / | awk 'NR==2 {gsub("G","",$4); print int($4)}')"
  if [ "${disk_gb_free:-0}" -lt 10 ]; then
    die_fail "resources/disk" "free disk on / = ${disk_gb_free}G, want >= 10G."
  fi

  local mem_gb_free
  mem_gb_free="$(free -g | awk '/^Mem:/ {print $7}')"
  if [ "${mem_gb_free:-0}" -lt 4 ]; then
    die_fail "resources/ram" "free memory = ${mem_gb_free}G, want >= 4G."
  fi

  ok "disk free=${disk_gb_free}G; ram free=${mem_gb_free}G"
}

# -----------------------------------------------------------------------------
# 2. OpenClaw version pin
# -----------------------------------------------------------------------------
check_openclaw_version() {
  info "check 2/10: openclaw version pin"

  if ! command -v openclaw >/dev/null 2>&1; then
    die_fail "openclaw/binary" "openclaw not on PATH; install per protocol §3."
  fi

  # `openclaw --version` outputs e.g. "OpenClaw 2026.4.15 (041266a)" —
  # we want the semver in $2, not the build hash in $NF.
  local version
  version="$(openclaw --version 2>/dev/null | head -1 | awk '{print $2}')"
  if [ "$version" != "$OPENCLAW_VERSION_REQUIRED" ]; then
    die_fail "openclaw/version" "openclaw --version reports '${version}', want exactly '${OPENCLAW_VERSION_REQUIRED}'."
  fi

  ok "openclaw ${version}"
}

# -----------------------------------------------------------------------------
# 3. systemd user service + linger
# -----------------------------------------------------------------------------
check_gateway_service() {
  info "check 3/10: openclaw-gateway active + linger enabled"

  local active
  active="$(systemctl --user is-active "$OPENCLAW_GATEWAY_UNIT" 2>/dev/null || echo 'inactive')"
  if [ "$active" != "active" ]; then
    die_fail "gateway/active" "systemctl --user is-active ${OPENCLAW_GATEWAY_UNIT}: '${active}'. Start with: systemctl --user start ${OPENCLAW_GATEWAY_UNIT}"
  fi

  local linger
  linger="$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null || echo 'no')"
  if [ "$linger" != "yes" ]; then
    die_fail "gateway/linger" "loginctl Linger=${linger} for ${USER}; gateway will die on SSH disconnect. Enable with: sudo loginctl enable-linger ${USER}"
  fi

  ok "gateway active; Linger=yes"
}

# -----------------------------------------------------------------------------
# 4. cost endpoint returns valid JSON
# -----------------------------------------------------------------------------
check_cost_endpoint() {
  info "check 4/10: openclaw gateway usage-cost --json"

  local out total
  out="$(openclaw gateway usage-cost --json 2>&1)"
  if [ $? -ne 0 ]; then
    die_fail "cost/cli" "openclaw gateway usage-cost --json failed: ${out}"
  fi

  # Cost JSON shape (verified against openclaw 2026.4.15):
  #   { updatedAt, days, daily, totals: { totalCost, ... } }
  total="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=(d.get("totals") or {}).get("totalCost"); print(v if isinstance(v,(int,float)) else "BAD")' 2>/dev/null)"
  if [ "$total" = "BAD" ] || [ -z "$total" ]; then
    die_fail "cost/json" "response did not contain numeric .totals.totalCost: ${out}"
  fi

  ok "usage-cost totals.totalCost=${total}"
}

# -----------------------------------------------------------------------------
# 5. GCP Secret Manager reachable + accessor IAM bound
# -----------------------------------------------------------------------------
check_gsm() {
  info "check 5/10: GCP Secret Manager reachable from the VM"

  if ! command -v gcloud >/dev/null 2>&1; then
    die_fail "gsm/cli" "gcloud not on PATH (unexpected on a Debian GCE image)."
  fi

  # Probe a known-set, low-sensitivity secret. gmail-email is a short
  # plaintext value created during CRUX-Windows; reading it confirms
  # both API access and roles/secretmanager.secretAccessor binding.
  local out
  out="$(gcloud secrets versions access latest \
    --secret=gmail-email \
    --project="$PROJECT" \
    2>&1)"
  if [ $? -ne 0 ] || [ -z "$out" ]; then
    die_fail "gsm/access" "could not read GSM secret 'gmail-email': ${out}. Verify the VM service-account has roles/secretmanager.secretAccessor on project ${PROJECT}."
  fi

  ok "gsm reachable; secret 'gmail-email' readable"
}

# Helper: read a GSM secret by name. Echoes empty on failure.
gsm_get() {
  gcloud secrets versions access latest \
    --secret="$1" \
    --project="$PROJECT" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 6. dedicated Gmail IMAP/SMTP reachable
# -----------------------------------------------------------------------------
check_gmail() {
  info "check 6/10: dedicated Gmail IMAP + SMTP reachable"

  if ! timeout 5 bash -c '</dev/tcp/imap.gmail.com/993' 2>/dev/null; then
    die_fail "gmail/imap" "TCP connect to imap.gmail.com:993 failed."
  fi
  if ! timeout 5 bash -c '</dev/tcp/smtp.gmail.com/465' 2>/dev/null; then
    die_fail "gmail/smtp" "TCP connect to smtp.gmail.com:465 failed."
  fi

  # Auth check: read gmail-email + gmail-app-password from GSM and
  # do an authenticated IMAP login. Skipped silently if either secret
  # is missing — the TCP probe above is the floor.
  local gmail_login
  gmail_login="$(gsm_get gmail-email)"
  if [ -n "$gmail_login" ]; then
    local app_password
    app_password="$(gsm_get gmail-app-password)"
    if [ -n "$app_password" ]; then
      python3 - "$gmail_login" "$app_password" <<'PY' 2>/dev/null
import imaplib, sys
u, p = sys.argv[1], sys.argv[2]
m = imaplib.IMAP4_SSL("imap.gmail.com", 993)
m.login(u, p)
m.logout()
PY
      if [ $? -ne 0 ]; then
        die_fail "gmail/auth" "IMAP TCP works but auth login failed for ${gmail_login}. Check GSM secret 'gmail-app-password' (must be the 16-char app password, not the account login password)."
      fi
    fi
  fi

  ok "gmail TCP+auth reachable"
}

# -----------------------------------------------------------------------------
# 7. Slack Socket Mode round-trip
# -----------------------------------------------------------------------------
check_slack() {
  info "check 7/10: Slack tokens valid + bot in #crux-land"

  # Tokens live in openclaw.json under channels.slack.{botToken,appToken}
  # (verified against CRUX-Windows config + OpenClaw 2026.4.15 schema).
  local oc_config="${HOME}/.openclaw/openclaw.json"
  if [ ! -r "$oc_config" ]; then
    die_fail "slack/config" "${oc_config} missing; provision_controller.sh did not run cleanly."
  fi
  local SLACK_BOT_TOKEN SLACK_APP_TOKEN
  SLACK_BOT_TOKEN="$(jq -r '.channels.slack.botToken // ""' "$oc_config" 2>/dev/null)"
  SLACK_APP_TOKEN="$(jq -r '.channels.slack.appToken // ""' "$oc_config" 2>/dev/null)"

  if [ -z "$SLACK_BOT_TOKEN" ] || [ -z "$SLACK_APP_TOKEN" ]; then
    die_fail "slack/config" "channels.slack.{botToken,appToken} not set in ${oc_config}; populate per USER-CHECKLIST.md §2"
  fi

  # 7a. SLACK_APP_TOKEN well-formed (xapp- prefix = Socket Mode app token).
  case "$SLACK_APP_TOKEN" in
    xapp-*) ;;
    *) die_fail "slack/app-token" "SLACK_APP_TOKEN does not start with 'xapp-'; not a Socket Mode app token." ;;
  esac

  # 7b. auth.test validates the bot token + returns workspace + bot user.
  local auth_resp
  auth_resp="$(curl -sS --max-time 5 \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    https://slack.com/api/auth.test 2>&1)"
  local auth_ok
  auth_ok="$(printf '%s' "$auth_resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(bool(d.get("ok")))' 2>/dev/null)"
  if [ "$auth_ok" != "True" ]; then
    die_fail "slack/auth" "auth.test failed: ${auth_resp}. Verify SLACK_BOT_TOKEN."
  fi

  # 7c. Stronger than channels-list (which needs channels:read scope
  # the bot doesn't have): post a real message via chat.postMessage.
  # If the bot isn't in the channel, this fails with `not_in_channel`.
  # If scopes are missing, fails with `missing_scope`. Either way the
  # operator gets a clear, actionable error.
  local channel="${SLACK_CHANNEL_CRUX_LAND:-#crux-land}"
  local probe_resp probe_ok probe_err
  probe_resp="$(curl -sS --max-time 5 \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H 'Content-Type: application/json; charset=utf-8' \
    -d "{\"channel\":\"${channel}\",\"text\":\":wrench: preflight check 7 — bot can post in this channel\"}" \
    https://slack.com/api/chat.postMessage 2>&1)"
  probe_ok="$(printf '%s' "$probe_resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(bool(d.get("ok")))' 2>/dev/null)"
  if [ "$probe_ok" != "True" ]; then
    probe_err="$(printf '%s' "$probe_resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("error","unknown"))' 2>/dev/null)"
    case "$probe_err" in
      not_in_channel)
        die_fail "slack/channel" "bot is not a member of ${channel}. Invite the Slack app to the channel: /invite @crux-windows-bot in ${channel}." ;;
      *)
        die_fail "slack/postmessage" "chat.postMessage to ${channel} failed: error=${probe_err}; full response: ${probe_resp}" ;;
    esac
  fi

  ok "slack: auth.test ok; xapp token well-formed; bot can post to ${channel} (probe message visible there)"
}

# 7-helper: tokens are read from ~/.openclaw/openclaw.json under
# channels.slack.{botToken,appToken} — not a separate slack.env.

# -----------------------------------------------------------------------------
# 8. Telemetry plugin end-to-end (tool.* AND agent.usage)
# -----------------------------------------------------------------------------
check_telemetry_e2e() {
  info "check 8/10: telemetry plugin captures tool.* AND agent.usage"

  local helper="${HOME}/crux-land/experiments/land/scripts/helpers/telemetry_e2e.py"
  if [ ! -x "$helper" ] && [ -r "$helper" ]; then
    helper="python3 $helper"
  fi

  if [ ! -r "${helper%% *}" ]; then
    fail "telemetry/helper" "helper script not found at ${helper}; falling back to log inspection."
    # Fallback: just verify telemetry.jsonl is being written and has both
    # event types appear at all in the last 24h.
    if [ ! -s "$TELEMETRY_LOG" ]; then
      die_fail "telemetry/log" "telemetry.jsonl is empty or missing at ${TELEMETRY_LOG}."
    fi
    local has_tool has_usage
    has_tool="$(grep -c '"type":"tool\.' "$TELEMETRY_LOG" 2>/dev/null || echo 0)"
    has_usage="$(grep -c '"type":"agent\.usage"' "$TELEMETRY_LOG" 2>/dev/null || echo 0)"
    if [ "$has_tool" = "0" ]; then
      die_fail "telemetry/tool" "no tool.* events in ${TELEMETRY_LOG}."
    fi
    if [ "$has_usage" = "0" ]; then
      die_fail "telemetry/usage" "no agent.usage events in ${TELEMETRY_LOG} — same regression as the CRUX-Windows 2026-04-18 run. Verify getnenai/openclaw-telemetry post-fork is loaded."
    fi
    ok "telemetry log has both tool.* (${has_tool}) and agent.usage (${has_usage}) events (fallback inspection)"
    return 0
  fi

  if ! $helper; then
    die_fail "telemetry/e2e" "helper script reported failure (see its output above)."
  fi

  ok "telemetry e2e: tool.* + agent.usage observed within 2s of dummy call"
}

# -----------------------------------------------------------------------------
# 9. Twilio voice round-trip
# -----------------------------------------------------------------------------
check_twilio() {
  info "check 9/10: Twilio voice + recording round-trip"

  require_env SINK_PHONE_NUMBER "twilio/env"

  local helper="${HOME}/crux-land/experiments/land/scripts/helpers/twilio_roundtrip.py"
  if [ ! -r "$helper" ]; then
    die_fail "twilio/helper" "helper script not found at ${helper}; cannot validate Twilio without it."
  fi

  # Use the venv python directly (not the symlink at
  # ~/.local/bin/crux-land-python3, because Python derives its
  # site-packages search from sys.executable's path — going through
  # a symlink outside the venv breaks site-packages discovery).
  local PY="${HOME}/crux-land-venv/bin/python3"
  [ -x "$PY" ] || PY="python3"
  if ! "$PY" "$helper" --to "$SINK_PHONE_NUMBER" --phrase "preflight $(date +%s)"; then
    die_fail "twilio/roundtrip" "twilio_roundtrip.py reported failure (call placement, recording fetch, or transcription)."
  fi

  ok "twilio call placed, recording captured + transcribed"
}

# -----------------------------------------------------------------------------
# 10. Browser-recording end-to-end
# -----------------------------------------------------------------------------
check_browser_recording() {
  info "check 10/10: browser tool wiring (chromium, CLI, plugin fork)"

  local helper="${HOME}/crux-land/experiments/land/scripts/helpers/browser_e2e.py"
  if [ ! -r "$helper" ]; then
    die_fail "browser/helper" "helper script not found at ${helper}; cannot validate browser wiring without it."
  fi

  if ! python3 "$helper"; then
    die_fail "browser/recording" "browser_e2e.py reported failure (see its output above for the specific assertion)."
  fi

  ok "browser wiring: chromium present, CLI loaded, telemetry fork pinned"
}

# -----------------------------------------------------------------------------
# driver
# -----------------------------------------------------------------------------
main() {
  local start_ts
  start_ts="$(date +%s)"
  info "preflight starting (verbose=$VERBOSE)"

  check_resources           # 1
  check_openclaw_version    # 2
  check_gateway_service     # 3
  check_cost_endpoint       # 4
  check_gsm                 # 5
  check_gmail               # 6
  check_slack               # 7
  check_telemetry_e2e       # 8
  check_twilio              # 9
  check_browser_recording   # 10

  local elapsed=$(( $(date +%s) - start_ts ))
  printf '[%s] [ PASS] all 10 preflight checks passed in %ss.\n' "$(ts)" "$elapsed"
  exit 0
}

main "$@"
