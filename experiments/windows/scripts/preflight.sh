#!/usr/bin/env bash
# preflight.sh - CRUX-Windows experiment preflight validator.
#
# Runs on the controller VM. Exits 0 if every check passes, 1 on the first
# failure with a human-actionable hint. Does not mutate state.
#
# Usage:
#   bash preflight.sh          # quiet-on-success
#   bash preflight.sh --verbose
#
# Typical invocation from a laptop:
#   gcloud compute ssh crux-windows-ctrl --tunnel-through-iap \
#     --zone=us-central1-a -- bash ~/crux-windows/scripts/preflight.sh

set -u

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    *) ;;
  esac
done

# ---- config (controller-side paths) ------------------------------------------
DEXBOX_URL="http://localhost:8600"
CREDS_JSON="${HOME}/.dexbox/shared/creds.json"
DEXBOX_LOG="${HOME}/.dexbox/dexbox.log"
WINDOWS_HOST="<windows-vm-ip>"
WINDOWS_USER="dexbox"
TMP_PNG="$(mktemp -t preflight-shot.XXXXXX.png)"
trap 'rm -f "$TMP_PNG"' EXIT

# ---- logging helpers ---------------------------------------------------------
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

info() { [ "$VERBOSE" -eq 1 ] && printf '[%s] [INFO ] %s\n' "$(ts)" "$*" >&2; return 0; }

fail() {
  local check="$1"; shift
  printf '[%s] [FAIL ] %s: %s\n' "$(ts)" "$check" "$*" >&2
}

die_fail() {
  local check="$1"; shift
  fail "$check" "$*"
  exit 1
}

ok() { [ "$VERBOSE" -eq 1 ] && printf '[%s] [ OK  ] %s\n' "$(ts)" "$*" >&2; return 0; }

# -----------------------------------------------------------------------------
# 1. Controller-side: dexbox server health
# -----------------------------------------------------------------------------
check_dexbox_server() {
  info "check 1/7: dexbox server health on ${DEXBOX_URL}"

  local health_code
  health_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    "${DEXBOX_URL}/health" 2>/dev/null || echo '000')"

  if [ "$health_code" != "200" ]; then
    fail "dexbox/health" "GET ${DEXBOX_URL}/health returned HTTP ${health_code} (expected 200)."
    print_dexbox_restart_hint
    exit 1
  fi

  local desktops_body
  desktops_body="$(curl -sS --max-time 5 "${DEXBOX_URL}/desktops" 2>/dev/null || echo '')"

  if [ -z "$desktops_body" ]; then
    fail "dexbox/desktops" "empty response from GET ${DEXBOX_URL}/desktops."
    print_dexbox_restart_hint
    exit 1
  fi

  local parser_py='
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f"PARSE_ERR:{e}"); sys.exit(0)
desktops = data if isinstance(data, list) else data.get("desktops", [])
for d in desktops:
    state = d.get("state")
    if d.get("name") == "win" and d.get("type") == "rdp" and state in ("reachable", "connected"):
        print("OK"); sys.exit(0)
print("NO_MATCH:" + json.dumps(desktops)[:500])
'
  local parsed
  parsed="$(printf '%s' "$desktops_body" | python3 -c "$parser_py" 2>/dev/null)"
  [ -z "$parsed" ] && parsed="PARSE_ERR:python helper failed"

  case "$parsed" in
    OK) ok "dexbox server healthy; desktop 'win' (rdp) reachable" ;;
    PARSE_ERR:*)
      fail "dexbox/desktops" "response was not valid JSON (${parsed#PARSE_ERR:})."
      print_dexbox_restart_hint
      exit 1
      ;;
    *)
      fail "dexbox/desktops" "no desktop with name=win, type=rdp, state=reachable. body=${parsed#NO_MATCH:}"
      print_dexbox_restart_hint
      exit 1
      ;;
  esac
}

print_dexbox_restart_hint() {
  printf '[%s] [HINT ] restart dexbox with: tmux kill-session -t dexbox && tmux new-session -d -s dexbox '"'"'exec /usr/local/bin/dexbox start 2>&1 | tee -a ~/.dexbox/dexbox.log'"'"'\n' "$(ts)" >&2
  printf '[%s] [HINT ] last 20 lines of %s:\n' "$(ts)" "$DEXBOX_LOG" >&2
  if [ -r "$DEXBOX_LOG" ]; then
    tail -n 20 "$DEXBOX_LOG" 2>&1 | sed 's/^/    /' >&2
  else
    printf '    (log file not readable or missing)\n' >&2
  fi
}

# -----------------------------------------------------------------------------
# 2. Controller-side: guacd container
# -----------------------------------------------------------------------------
check_guacd() {
  info "check 2/7: guacd container + TCP/4822"

  local status
  status="$(docker ps --filter ancestor=guacamole/guacd --format '{{.Status}}' 2>/dev/null || echo '')"

  if [ -z "$status" ]; then
    die_fail "guacd/container" "no running container for image guacamole/guacd. Start it with docker compose up, then re-run."
  fi

  # Must be "Up" AND include either "healthy" or "health: starting"
  if ! printf '%s' "$status" | grep -q 'Up'; then
    die_fail "guacd/container" "container present but not Up: '${status}'."
  fi

  if ! printf '%s' "$status" | grep -Eq 'healthy|health: starting'; then
    die_fail "guacd/container" "container is Up but health state is not healthy / starting: '${status}'. Check: docker inspect --format='{{json .State.Health}}' \$(docker ps --filter ancestor=guacamole/guacd -q)"
  fi

  # Listening socket on :4822
  if ! ss -ltn 2>/dev/null | grep -q ':4822'; then
    die_fail "guacd/port" "no LISTEN socket on :4822. 'ss -ltn | grep 4822' returned empty. guacd is not accepting connections yet."
  fi

  ok "guacd container status='${status}'; :4822 listening"
}

# -----------------------------------------------------------------------------
# 3. Windows-side: SSH auth works
# -----------------------------------------------------------------------------
# Cache the password once so we don't re-parse on every SSH call.
WINDOWS_PASSWORD=""

load_windows_password() {
  if [ ! -r "$CREDS_JSON" ]; then
    die_fail "creds/file" "cannot read ${CREDS_JSON}. Without the admin password the Windows checks can't proceed."
  fi
  WINDOWS_PASSWORD="$(python3 -c "import json; print(json.load(open('${CREDS_JSON}'))['windows_admin_password'])" 2>/dev/null || echo '')"
  if [ -z "$WINDOWS_PASSWORD" ]; then
    die_fail "creds/parse" "creds.json is readable but windows_admin_password key is missing or empty."
  fi
}

# Wrapper: run a command over SSH to the Windows box. Prints stdout; returns ssh exit.
ssh_win() {
  local cmd="$1"
  sshpass -p "$WINDOWS_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 \
    -o LogLevel=ERROR \
    "${WINDOWS_USER}@${WINDOWS_HOST}" "$cmd"
}

# Run a raw PowerShell payload, base64-encoding to avoid nested quoting hell.
ssh_win_ps() {
  local payload="$1"
  local encoded
  encoded="$(python3 -c 'import sys, base64; print(base64.b64encode(sys.argv[1].encode("utf-16-le")).decode())' "$payload")"
  ssh_win "powershell -NoProfile -EncodedCommand $encoded"
}

check_ssh_auth() {
  info "check 3/7: SSH auth to ${WINDOWS_USER}@${WINDOWS_HOST}"

  if ! command -v sshpass >/dev/null 2>&1; then
    die_fail "ssh/sshpass" "sshpass binary not in PATH. Install with: sudo apt-get install -y sshpass"
  fi

  local whoami_out rc
  whoami_out="$(ssh_win 'whoami' 2>&1)"
  rc=$?

  if [ $rc -ne 0 ]; then
    die_fail "ssh/auth" "ssh to ${WINDOWS_USER}@${WINDOWS_HOST} failed (rc=${rc}): ${whoami_out}"
  fi

  # normalize
  if ! printf '%s' "$whoami_out" | grep -qi 'dexbox'; then
    die_fail "ssh/whoami" "whoami returned '${whoami_out}', expected a string containing 'dexbox'."
  fi

  ok "SSH works; whoami='${whoami_out}'"
}

# -----------------------------------------------------------------------------
# 4. Windows-side: AutoAdminLogon registry keys
# -----------------------------------------------------------------------------
check_autologon_registry() {
  info "check 4/7: Winlogon AutoAdminLogon registry keys"

  # PowerShell on the far side. Emit KEY=VALUE lines we can grep.
  local ps_payload='$k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$p = Get-ItemProperty $k
Write-Output ("AutoAdminLogon=" + $p.AutoAdminLogon)
Write-Output ("DefaultUserName=" + $p.DefaultUserName)'

  local out rc
  out="$(ssh_win_ps "$ps_payload" 2>&1)"
  rc=$?
  if [ $rc -ne 0 ]; then
    die_fail "autologon/read" "could not read Winlogon registry (rc=${rc}): ${out}"
  fi

  local auto user
  auto="$(printf '%s\n' "$out" | awk -F= '/^AutoAdminLogon=/{print $2}' | tr -d '\r')"
  user="$(printf '%s\n' "$out" | awk -F= '/^DefaultUserName=/{print $2}' | tr -d '\r')"

  if [ "$auto" != "1" ]; then
    die_fail "autologon/AutoAdminLogon" "HKLM:\\...\\Winlogon AutoAdminLogon='${auto}' (want '1'). AutoAdminLogon is off; Windows will land on LogonUI after boot."
  fi
  if [ "$user" != "dexbox" ]; then
    die_fail "autologon/DefaultUserName" "HKLM:\\...\\Winlogon DefaultUserName='${user}' (want 'dexbox')."
  fi

  ok "AutoAdminLogon=1, DefaultUserName=dexbox"
}

# -----------------------------------------------------------------------------
# 5. Windows-side: dexbox user is Active on console
# -----------------------------------------------------------------------------
check_console_session() {
  info "check 5/7: console session state for 'dexbox'"

  local out rc
  out="$(ssh_win 'query session' 2>&1)"
  rc=$?
  # `query session` can return rc=1 even on success (warns to stderr when there
  # are disconnected sessions). Trust the output shape instead: if we see the
  # SESSIONNAME header line, the command ran.
  if ! printf '%s\n' "$out" | grep -q 'SESSIONNAME'; then
    die_fail "session/query" "'query session' failed (rc=${rc}): ${out}"
  fi

  # Find a line whose USERNAME column is exactly 'dexbox' and STATE is 'Active'.
  # Column layout (typical):
  #  SESSIONNAME       USERNAME                 ID  STATE   TYPE        DEVICE
  # We'll pick columns by position-independent awk: any line containing 'dexbox'
  # with 'Active' token.
  local state_line
  state_line="$(printf '%s\n' "$out" | awk '
    tolower($0) ~ /dexbox/ {
      # find tokens
      user=""; state="";
      for (i=1; i<=NF; i++) {
        if (tolower($i) == "dexbox") user=$i
        if ($i == "Active" || $i == "Disc" || $i == "Conn") state=$i
      }
      if (user != "") {
        print state
        exit
      }
    }
  ')"

  if [ -z "$state_line" ]; then
    die_fail "session/user" "no 'dexbox' row in 'query session' output:\n${out}"
  fi

  if [ "$state_line" = "Disc" ]; then
    fail "session/state" "dexbox session is Disc (disconnected). AutoAdminLogon likely failed on boot; Windows is sitting at LogonUI."
    printf '[%s] [HINT ] reboot the VM to retry auto-login: gcloud compute instances reset windows-golden-bake --zone=us-central1-a\n' "$(ts)" >&2
    exit 1
  fi

  if [ "$state_line" != "Active" ]; then
    die_fail "session/state" "dexbox session state='${state_line}', want 'Active'."
  fi

  ok "dexbox session is Active on console"
}

# -----------------------------------------------------------------------------
# 6. End-to-end: desktop up + screenshot pixel analysis
# -----------------------------------------------------------------------------
check_e2e_screenshot() {
  info "check 6/7: e2e screenshot via ${DEXBOX_URL}"

  # 6a: POST /desktops/win?action=up
  local up_code
  up_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    -X POST "${DEXBOX_URL}/desktops/win?action=up" 2>/dev/null || echo '000')"
  if [ "$up_code" != "200" ]; then
    die_fail "e2e/up" "POST /desktops/win?action=up returned HTTP ${up_code} (want 200)."
  fi
  info "  desktop 'win' up; sleeping 3s for RDP to settle"
  sleep 3

  # 6b: POST /actions to take a screenshot
  local body='{"type":"computer_20250124","action":"screenshot"}'
  local http_code
  http_code="$(curl -sS --max-time 20 \
    -o "$TMP_PNG" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H 'Accept: image/png' \
    -X POST \
    --data "$body" \
    "${DEXBOX_URL}/actions?model=claude-sonnet-4-5-20250929&desktop=win" \
    2>/dev/null || echo '000')"

  if [ "$http_code" != "200" ]; then
    # Show the response body if it's small and not a real PNG
    local preview=""
    if [ -s "$TMP_PNG" ]; then preview="$(head -c 300 "$TMP_PNG" 2>/dev/null | tr -d '\r')"; fi
    die_fail "e2e/screenshot" "POST /actions returned HTTP ${http_code}; body preview: ${preview}"
  fi

  if [ ! -s "$TMP_PNG" ]; then
    die_fail "e2e/screenshot" "screenshot response was empty."
  fi

  # 6c: pixel analysis. Prefer the venv python (PIL is installed there for the
  # harness); fall back to system python3 if the venv isn't present.
  local py_bin="python3"
  if [ -x "$HOME/crux-windows-venv/bin/python3" ]; then
    py_bin="$HOME/crux-windows-venv/bin/python3"
  fi
  local py_out py_rc
  py_out="$("$py_bin" - "$TMP_PNG" <<'PY' 2>&1
import sys
from PIL import Image

path = sys.argv[1]
try:
    img = Image.open(path)
    img.load()
except Exception as e:
    print(f"INVALID_PNG:{e}")
    sys.exit(2)

size = img.size
rgb = img.convert("RGB")
uniq = len(set(rgb.getdata()))
print(f"SIZE={size[0]}x{size[1]}")
print(f"UNIQUE={uniq}")

if size != (1024, 768):
    print("BAD_SIZE")
    sys.exit(3)
if uniq <= 1000:
    print("LOW_UNIQUE")
    sys.exit(4)
print("OK")
PY
)"
  py_rc=$?

  local uniq size
  size="$(printf '%s\n' "$py_out" | awk -F= '/^SIZE=/{print $2}')"
  uniq="$(printf '%s\n' "$py_out" | awk -F= '/^UNIQUE=/{print $2}')"

  case $py_rc in
    0)
      ok "screenshot OK: size=${size}, unique_rgb=${uniq}"
      printf '[%s] [ OK  ] screenshot size=%s unique_rgb=%s\n' "$(ts)" "$size" "$uniq"
      ;;
    2)
      die_fail "e2e/pixels" "screenshot is not a valid PNG: ${py_out}"
      ;;
    3)
      die_fail "e2e/pixels" "screenshot size=${size}, want 1024x768. dexbox may be using the wrong display geometry."
      ;;
    4)
      fail "e2e/pixels" "screenshot has only ${uniq} unique RGB colors (<=1000 threshold). Likely a lock screen or blank frame, not a real desktop."
      printf '[%s] [HINT ] session may be locked. Re-check console state (query session) and consider rebooting windows-golden-bake.\n' "$(ts)" >&2
      exit 1
      ;;
    *)
      die_fail "e2e/pixels" "unexpected pixel-check failure (rc=${py_rc}): ${py_out}"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# 7. Controller-side: telemetry plugin will capture events during the run
# -----------------------------------------------------------------------------
# Verifies the OpenClaw telemetry plugin plumbing without actually invoking an
# agent turn (preflight is read-only). Four sub-assertions:
#   a) plugins.entries.telemetry.enabled=true in ~/.openclaw/openclaw.json
#   b) `openclaw plugins list` reports status=loaded for the telemetry plugin
#   c) the configured (or default) output path has a writable parent directory
#   d) if telemetry.jsonl already has content, surface the newest event ts so
#      an operator can eyeball that events have been captured before
check_telemetry_plugin() {
  info "check 7/7: telemetry plugin will capture events during the run"

  local config_path="${HOME}/.openclaw/openclaw.json"

  if [ ! -r "$config_path" ]; then
    die_fail "telemetry/config" "cannot read ${config_path}. Is OpenClaw installed for this user?"
  fi

  # 7a: verify plugins.entries.telemetry.enabled and discover the output path.
  local parser_py='
import json, os, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except Exception as e:
    print(f"PARSE_ERR:{e}"); sys.exit(0)
entry = (d.get("plugins", {}) or {}).get("entries", {}).get("telemetry")
if not isinstance(entry, dict):
    print("MISSING"); sys.exit(0)
if entry.get("enabled") is not True:
    print("DISABLED"); sys.exit(0)
# The plugin reads config under .config.*; fall back to flat keys for robustness.
cfg = entry.get("config", {}) if isinstance(entry.get("config"), dict) else {}
file_path = cfg.get("filePath") or entry.get("filePath") or \
    os.path.expanduser("~/.openclaw/logs/telemetry.jsonl")
print("OK:" + file_path)
'
  local parsed
  parsed="$(python3 -c "$parser_py" "$config_path" 2>/dev/null)"
  [ -z "$parsed" ] && parsed="PARSE_ERR:python helper failed"

  local telemetry_path=""
  case "$parsed" in
    OK:*)
      telemetry_path="${parsed#OK:}"
      ok "openclaw.json: plugins.entries.telemetry.enabled=true; filePath=${telemetry_path}"
      ;;
    MISSING)
      die_fail "telemetry/config" "plugins.entries.telemetry is missing from ${config_path}. Install with: openclaw plugins install knostic/openclaw-telemetry"
      ;;
    DISABLED)
      die_fail "telemetry/config" "plugins.entries.telemetry.enabled != true in ${config_path}. Set it to true and restart the gateway."
      ;;
    PARSE_ERR:*)
      die_fail "telemetry/config" "openclaw.json parse failed (${parsed#PARSE_ERR:})."
      ;;
    *)
      die_fail "telemetry/config" "unexpected parser output: ${parsed}"
      ;;
  esac

  # 7b: `openclaw plugins list` reports status=loaded.
  if ! command -v openclaw >/dev/null 2>&1; then
    die_fail "telemetry/cli" "openclaw binary not in PATH; cannot verify plugin load state."
  fi

  local plist_out
  plist_out="$(openclaw plugins list 2>&1)"
  # Table wraps long plugin ids across lines (e.g. "telemetr" + "y"); match
  # either the full id on one line or a loaded row that mentions global:telemetry/.
  if ! printf '%s\n' "$plist_out" | grep -Eq '(telemetry|telemetr).*loaded|global:telemetry/.*loaded'; then
    fail "telemetry/load" "openclaw plugins list does not show telemetry with status=loaded."
    printf '%s\n' "$plist_out" | grep -iE 'telemetr|loaded' | sed 's/^/    /' >&2
    exit 1
  fi
  ok "openclaw plugins list: telemetry plugin is loaded"

  # 7c: output path's parent dir exists and is writable by the current user.
  local parent_dir
  parent_dir="$(dirname "$telemetry_path")"
  if [ ! -d "$parent_dir" ]; then
    die_fail "telemetry/path" "telemetry output dir ${parent_dir} does not exist. Create with: mkdir -p '${parent_dir}'"
  fi
  if [ ! -w "$parent_dir" ]; then
    die_fail "telemetry/path" "telemetry output dir ${parent_dir} is not writable by $(id -un). The plugin's file writer will silently drop events."
  fi
  ok "telemetry output dir ${parent_dir} exists and is writable"

  # 7d (optional): if telemetry.jsonl already has content, show newest ts.
  if [ -s "$telemetry_path" ]; then
    local last_ts
    last_ts="$(python3 - "$telemetry_path" <<'PY' 2>/dev/null
import json, sys, datetime
last = None
try:
    with open(sys.argv[1]) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                o = json.loads(line)
                ts = o.get("ts")
                if isinstance(ts, (int, float)):
                    last = ts
            except Exception:
                pass
except Exception:
    sys.exit(0)
if last is not None:
    dt = datetime.datetime.fromtimestamp(last/1000, tz=datetime.timezone.utc)
    print(dt.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
    if [ -n "$last_ts" ]; then
      ok "telemetry.jsonl already has events; newest ts=${last_ts}"
    else
      ok "telemetry.jsonl exists but newest ts could not be parsed (non-fatal)"
    fi
  else
    ok "telemetry.jsonl is absent or empty (expected on first run — plugin will create it)"
  fi
}

# -----------------------------------------------------------------------------
# driver
# -----------------------------------------------------------------------------
main() {
  local start_ts
  start_ts="$(date +%s)"
  info "preflight starting (verbose=$VERBOSE)"

  check_dexbox_server
  check_guacd
  load_windows_password
  check_ssh_auth
  check_autologon_registry
  check_console_session
  check_e2e_screenshot
  check_telemetry_plugin

  local elapsed=$(( $(date +%s) - start_ts ))
  printf '[%s] [ PASS] all 7 preflight checks passed in %ss.\n' "$(ts)" "$elapsed"
  exit 0
}

main "$@"
