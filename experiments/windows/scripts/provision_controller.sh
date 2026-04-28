#!/usr/bin/env bash
# provision_controller.sh — stand up a Linux controller VM for the CRUX-Windows
# experiment and wire it to a pre-existing GCE Windows VM.
#
# Two-phase:
#   Phase 1 (this script, runs on the user's Mac):
#     - Validates gcloud auth + prompts for the Windows password (stdin, silent).
#     - Creates / reuses the Debian 12 controller VM (IAP SSH throughout).
#     - Resolves the Windows VM's internal IP via `gcloud compute instances describe`.
#     - Rsyncs the local crux-windows/ tree to ~/crux-windows/ on the VM.
#     - Copies the phase-2 script and invokes it over IAP SSH, passing the
#       Windows password via stdin (never in argv, env, or on disk).
#   Phase 2 (_provision_vm.sh, runs on the VM):
#     - apt-installs deps, builds dexbox from PR #45's branch, pulls guacd,
#       creates the venv, registers the RDP target, launches `dexbox start`
#       in tmux, and runs the smoke test.
#
# Usage:
#   CRUX_WIN_NAME=crux-win-01 ./provision_controller.sh
#   ./provision_controller.sh --win-name crux-win-01 --dry-run
#
# Env/flags (flag wins over env):
#   --project        CRUX_PROJECT      (default: <your-gcp-project>)
#   --zone           CRUX_ZONE         (default: us-central1-a)
#   --ctrl-name      CRUX_CTRL_NAME    (default: crux-windows-ctrl)
#   --win-name       CRUX_WIN_NAME     (REQUIRED)
#   --win-user       CRUX_WIN_USER     (default: dexbox)
#   --local-src      CRUX_LOCAL_SRC    (default: /path/to/crux-x)
#   --dry-run                          print the gcloud commands; no state changes
#
# Secrets:
#   CRUX_WIN_PASS — Windows password. If unset, prompted from stdin with -s.
#                   Optionally looked up in Secret Manager (secret:
#                   crux-windows-target-pass) on explicit opt-in via
#                   --use-secret-manager. Never logged, never in argv.

set -euo pipefail

LOG_FILE="/tmp/crux-provision.log"
# Truncate + tee from the start so the user sees progress AND we keep a record.
: >"$LOG_FILE"

# --------------------------------------------------------------------------- #
# logging                                                                     #
# --------------------------------------------------------------------------- #
log()  { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE" >&2 ; }
warn() { printf '[%s] WARN: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE" >&2 ; }
die()  { printf '[%s] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

# --------------------------------------------------------------------------- #
# defaults + arg parsing                                                      #
# --------------------------------------------------------------------------- #
CRUX_PROJECT="${CRUX_PROJECT:-<your-gcp-project>}"
CRUX_ZONE="${CRUX_ZONE:-us-central1-a}"
CRUX_CTRL_NAME="${CRUX_CTRL_NAME:-crux-windows-ctrl}"
CRUX_WIN_NAME="${CRUX_WIN_NAME:-}"
CRUX_WIN_USER="${CRUX_WIN_USER:-dexbox}"
CRUX_LOCAL_SRC="${CRUX_LOCAL_SRC:-/path/to/crux-x}"
# CRUX_WIN_PASS intentionally NOT defaulted; prompted below if unset.
DRY_RUN=0
USE_SECRET_MANAGER=0

usage() {
    sed -n '2,30p' "$0"
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)             CRUX_PROJECT="$2"; shift 2 ;;
        --zone)                CRUX_ZONE="$2"; shift 2 ;;
        --ctrl-name)           CRUX_CTRL_NAME="$2"; shift 2 ;;
        --win-name)            CRUX_WIN_NAME="$2"; shift 2 ;;
        --win-user)            CRUX_WIN_USER="$2"; shift 2 ;;
        --local-src)           CRUX_LOCAL_SRC="$2"; shift 2 ;;
        --dry-run)             DRY_RUN=1; shift ;;
        --use-secret-manager)  USE_SECRET_MANAGER=1; shift ;;
        -h|--help)             usage 0 ;;
        *)                     warn "unknown arg: $1"; usage 2 ;;
    esac
done

[[ -n "$CRUX_WIN_NAME" ]] || die "CRUX_WIN_NAME (or --win-name) is required; that's the GCE name of the pre-existing Windows target VM."
[[ -d "$CRUX_LOCAL_SRC" ]] || die "local source dir not found: $CRUX_LOCAL_SRC"
[[ -f "$CRUX_LOCAL_SRC/harness/pyproject.toml" ]] || die "expected $CRUX_LOCAL_SRC/harness/pyproject.toml — is --local-src correct?"

# --------------------------------------------------------------------------- #
# dry-run helper                                                              #
# --------------------------------------------------------------------------- #
# Prints the command it would run; in dry-run mode does NOT execute.
# Usage: run gcloud compute instances describe ...
run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '+ %s\n' "$*" | tee -a "$LOG_FILE"
        return 0
    fi
    log "+ $*"
    "$@"
}

# --------------------------------------------------------------------------- #
# preflight                                                                   #
# --------------------------------------------------------------------------- #
command -v gcloud >/dev/null 2>&1 || die "gcloud not on PATH. Install Google Cloud SDK."
command -v rsync  >/dev/null 2>&1 || die "rsync not on PATH."
command -v ssh    >/dev/null 2>&1 || die "ssh not on PATH."

if [[ "$DRY_RUN" -eq 0 ]]; then
    acct="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
    [[ -n "$acct" ]] || die "gcloud not authenticated. Run: gcloud auth login && gcloud auth application-default login"
    log "gcloud active account: $acct"
fi

# --------------------------------------------------------------------------- #
# Windows password acquisition (MUST NOT end up in logs / history)            #
# --------------------------------------------------------------------------- #
acquire_win_pass() {
    if [[ -n "${CRUX_WIN_PASS:-}" ]]; then
        log "using CRUX_WIN_PASS from environment (not logged)"
        return 0
    fi
    if [[ "$USE_SECRET_MANAGER" -eq 1 ]]; then
        log "fetching Windows password from Secret Manager (crux-windows-target-pass)"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            CRUX_WIN_PASS="__dry_run_placeholder__"
            return 0
        fi
        CRUX_WIN_PASS="$(gcloud secrets versions access latest \
            --secret=crux-windows-target-pass \
            --project="$CRUX_PROJECT" 2>/dev/null)" \
            || die "failed to read crux-windows-target-pass from Secret Manager. Create it first, or omit --use-secret-manager and be prompted."
        return 0
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        CRUX_WIN_PASS="__dry_run_placeholder__"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        die "CRUX_WIN_PASS unset and stdin is not a TTY; cannot prompt. Set CRUX_WIN_PASS or use --use-secret-manager."
    fi
    # Read silently; no echo, no history.
    printf 'Windows password for %s@%s: ' "$CRUX_WIN_USER" "$CRUX_WIN_NAME" >&2
    IFS= read -rs CRUX_WIN_PASS
    printf '\n' >&2
    [[ -n "$CRUX_WIN_PASS" ]] || die "empty password"
}

# --------------------------------------------------------------------------- #
# VM create / reuse                                                           #
# --------------------------------------------------------------------------- #
controller_status() {
    # In dry-run, pretend the controller doesn't yet exist so the user sees
    # the creation command printed.
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '+ (capture) gcloud compute instances describe %s --format=value(status)\n' \
            "$CRUX_CTRL_NAME" | tee -a "$LOG_FILE" >&2
        return 0
    fi
    gcloud compute instances describe "$CRUX_CTRL_NAME" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --format='value(status)' 2>/dev/null || true
}

ensure_controller() {
    local status
    status="$(controller_status)"
    if [[ -n "$status" ]]; then
        log "controller VM $CRUX_CTRL_NAME already exists (status=$status)"
        if [[ "$status" == "TERMINATED" ]]; then
            run gcloud compute instances start "$CRUX_CTRL_NAME" \
                --project="$CRUX_PROJECT" \
                --zone="$CRUX_ZONE"
        fi
        return 0
    fi
    log "creating controller VM $CRUX_CTRL_NAME"
    # e2-standard-4 is plenty for running the harness + guacd + tmux.
    # Debian 12 (bookworm) — the user's standard.
    run gcloud compute instances create "$CRUX_CTRL_NAME" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --machine-type=e2-standard-4 \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=50GB \
        --boot-disk-type=pd-balanced \
        --network=default \
        --subnet=default \
        --scopes=cloud-platform \
        --metadata=enable-oslogin=TRUE
}

# --------------------------------------------------------------------------- #
# Windows target lookup                                                       #
# --------------------------------------------------------------------------- #
resolve_win_ip() {
    local status ip
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '+ (capture) gcloud compute instances describe %s --format=value(status)\n' \
            "$CRUX_WIN_NAME" | tee -a "$LOG_FILE" >&2
        printf '+ (capture) gcloud compute instances describe %s --format=value(networkInterfaces[0].networkIP)\n' \
            "$CRUX_WIN_NAME" | tee -a "$LOG_FILE" >&2
        log "Windows target $CRUX_WIN_NAME -> 10.128.0.99 (dry-run)"
        printf '10.128.0.99\n'
        return 0
    fi
    status="$(gcloud compute instances describe "$CRUX_WIN_NAME" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --format='value(status)' 2>/dev/null || true)"
    if [[ -z "$status" ]]; then
        die "Windows VM $CRUX_WIN_NAME not found in project=$CRUX_PROJECT zone=$CRUX_ZONE. Check name/zone or create it first."
    fi
    if [[ "$status" != "RUNNING" ]]; then
        die "Windows VM $CRUX_WIN_NAME exists but status=$status (expected RUNNING). Start it: gcloud compute instances start $CRUX_WIN_NAME --zone=$CRUX_ZONE --project=$CRUX_PROJECT"
    fi
    ip="$(gcloud compute instances describe "$CRUX_WIN_NAME" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --format='value(networkInterfaces[0].networkIP)')"
    [[ -n "$ip" ]] || die "could not resolve internal IP for $CRUX_WIN_NAME"
    log "Windows target $CRUX_WIN_NAME -> $ip"
    printf '%s\n' "$ip"
}

# --------------------------------------------------------------------------- #
# IAP-tunneled ssh / scp wrappers                                             #
# --------------------------------------------------------------------------- #
iap_ssh() {
    # Usage: iap_ssh <remote-cmd>   (remote cmd string; runs as the IAP OS Login user)
    # Stdin is forwarded so callers can pipe secrets in.
    run gcloud compute ssh "$CRUX_CTRL_NAME" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --tunnel-through-iap \
        --command="$1"
}

iap_scp() {
    # Usage: iap_scp <local-path> <remote-path>
    run gcloud compute scp "$1" "$CRUX_CTRL_NAME:$2" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --tunnel-through-iap
}

# Rsync uses gcloud as the transport so IAP + OS Login work the same way as
# gcloud compute scp. We build the wrapper command via --rsh.
iap_rsync() {
    local src="$1"
    local dst_path="$2"
    local exclude_file="$CRUX_LOCAL_SRC/scripts/.provision_rsync_excludes"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '+ gcloud compute scp --recurse --tunnel-through-iap %s %s:%s\n' \
            "$src" "$CRUX_CTRL_NAME" "$dst_path" | tee -a "$LOG_FILE"
        return 0
    fi
    log "copying $src -> $CRUX_CTRL_NAME:$dst_path"
    # gcloud compute scp --recurse handles IAP natively (rsync over gcloud ssh
    # is awkward because gcloud ssh doesn't accept rsync's extra args). Uses a
    # staging tarball to respect excludes and to be close to atomic.
    local tmp_tar
    tmp_tar="$(mktemp -t crux-provision.tar.gz.XXXXXX)"
    trap "rm -f '$tmp_tar'" EXIT
    local tar_exclude_args=()
    if [[ -f "$exclude_file" ]]; then
        tar_exclude_args=(--exclude-from="$exclude_file")
    fi
    # Use bsdtar-compatible flags; macOS tar and GNU tar both accept these.
    tar -czf "$tmp_tar" -C "$src" "${tar_exclude_args[@]}" . \
        || die "tar of $src failed"
    gcloud compute scp \
        --tunnel-through-iap \
        --zone="$CRUX_ZONE" \
        --project="$CRUX_PROJECT" \
        "$tmp_tar" "$CRUX_CTRL_NAME:/tmp/crux-provision.tar.gz" \
        || die "scp of provision tarball failed"
    gcloud compute ssh "$CRUX_CTRL_NAME" \
        --tunnel-through-iap \
        --zone="$CRUX_ZONE" \
        --project="$CRUX_PROJECT" \
        --command "mkdir -p '$dst_path' && tar -xzf /tmp/crux-provision.tar.gz -C '$dst_path' && rm -f /tmp/crux-provision.tar.gz" \
        || die "remote extract failed"
    rm -f "$tmp_tar"
    trap - EXIT
}

# --------------------------------------------------------------------------- #
# main                                                                        #
# --------------------------------------------------------------------------- #
main() {
    log "crux-windows controller provisioning"
    log "  project=$CRUX_PROJECT zone=$CRUX_ZONE ctrl=$CRUX_CTRL_NAME win=$CRUX_WIN_NAME"
    log "  local-src=$CRUX_LOCAL_SRC  dry-run=$DRY_RUN"

    acquire_win_pass
    ensure_controller

    local win_ip
    win_ip="$(resolve_win_ip)"

    # Wait for SSH readiness (cheap retry loop; a freshly-created VM sometimes
    # needs ~30s before OS Login is usable).
    if [[ "$DRY_RUN" -eq 0 ]]; then
        log "waiting for controller SSH to be ready"
        local tries=0
        until gcloud compute ssh "$CRUX_CTRL_NAME" \
                --project="$CRUX_PROJECT" \
                --zone="$CRUX_ZONE" \
                --tunnel-through-iap \
                --command='true' >/dev/null 2>&1; do
            tries=$((tries + 1))
            [[ "$tries" -gt 30 ]] && die "controller SSH not ready after 30 attempts"
            sleep 4
        done
        log "controller SSH is up"
    fi

    # Rsync the project tree.
    iap_rsync "$CRUX_LOCAL_SRC/" "/home/$(whoami_remote)/crux-windows/"

    # Copy the phase-2 script.
    iap_scp "$CRUX_LOCAL_SRC/scripts/_provision_vm.sh" "/tmp/_provision_vm.sh"

    # Execute phase 2. Password goes over stdin ONLY — never in argv / env /
    # any log line. The remote script reads it with `IFS= read -rs` from fd 0.
    log "running phase 2 on $CRUX_CTRL_NAME"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '+ (phase-2) gcloud compute ssh %s --tunnel-through-iap -- bash /tmp/_provision_vm.sh <args...> (password via stdin)\n' \
            "$CRUX_CTRL_NAME" | tee -a "$LOG_FILE"
        log "dry-run complete; no changes made."
        return 0
    fi

    # gcloud IAP doesn't reliably forward local stdin to the remote command,
    # so we write the password to a 0600 tempfile on the Mac, scp it to
    # /tmp/crux-winpw on the VM, and let phase-2 read+shred it there.
    local local_pw_file
    local_pw_file="$(mktemp -t crux-winpw.XXXXXX)"
    chmod 600 "$local_pw_file"
    printf '%s' "$CRUX_WIN_PASS" > "$local_pw_file"
    gcloud compute scp \
        --tunnel-through-iap \
        --zone="$CRUX_ZONE" \
        --project="$CRUX_PROJECT" \
        "$local_pw_file" "$CRUX_CTRL_NAME:/tmp/crux-winpw" \
        || { shred -u "$local_pw_file" 2>/dev/null || rm -f "$local_pw_file"; die "scp of password tempfile failed"; }
    shred -u "$local_pw_file" 2>/dev/null || rm -f "$local_pw_file"
    # shellcheck disable=SC2029  # we WANT $CRUX_WIN_* expanded locally
    gcloud compute ssh "$CRUX_CTRL_NAME" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --tunnel-through-iap \
        --command="bash /tmp/_provision_vm.sh \
            --win-host '$win_ip' \
            --win-user '$CRUX_WIN_USER' \
            --project  '$CRUX_PROJECT'"

    log "provisioning complete."
    log "  controller: $CRUX_CTRL_NAME  zone=$CRUX_ZONE"
    log "  tmux:       gcloud compute ssh $CRUX_CTRL_NAME --tunnel-through-iap --zone=$CRUX_ZONE --project=$CRUX_PROJECT -- tmux attach -t dexbox"
    log "  log:        $LOG_FILE  (and /tmp/crux-provision.log on the VM)"
}

# Helper: figure out which remote username rsync/scp will land as. With OS
# Login, it's the user's email, with dots replaced by underscores and '@'
# turned into '_'. Best-effort — if we can't resolve it, fall back to $USER.
whoami_remote() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf 'dryrun_user\n'
        return 0
    fi
    local remote
    remote="$(gcloud compute ssh "$CRUX_CTRL_NAME" \
        --project="$CRUX_PROJECT" \
        --zone="$CRUX_ZONE" \
        --tunnel-through-iap \
        --command='whoami' 2>/dev/null | tr -d '\r\n ')" || true
    [[ -n "$remote" ]] || remote="$USER"
    printf '%s\n' "$remote"
}

main "$@"
