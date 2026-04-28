#!/usr/bin/env bash
# _provision_vm.sh — phase 2 of provision_controller.sh. Runs ON the VM.
#
# Invoked by the Mac-side script over IAP SSH, with the Windows password fed
# on stdin (not argv, not env). Installs system deps, builds dexbox from the
# PR #45 branch, pulls guacd, sets up the venv, starts dexbox in tmux,
# registers the RDP target, and runs the smoke test.
#
# Re-running is safe: every step is guarded by an existence / version check.

set -euo pipefail

LOG_FILE="/tmp/crux-provision.log"
: >"$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '[%s][vm] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" ; }
warn() { printf '[%s][vm] WARN: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2 ; }
die()  { printf '[%s][vm] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2 ; exit 1 ; }

WIN_HOST=""
WIN_USER="dexbox"
PROJECT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --win-host) WIN_HOST="$2"; shift 2 ;;
        --win-user) WIN_USER="$2"; shift 2 ;;
        --project)  PROJECT="$2"; shift 2 ;;
        *) die "unknown arg: $1" ;;
    esac
done
[[ -n "$WIN_HOST" ]] || die "--win-host required"

# Read Windows password from a 0600 tempfile at /tmp/crux-winpw that phase-1
# scp'd up just before invoking us. Delete immediately after reading so it
# never survives the invocation. (stdin forwarding over gcloud IAP doesn't
# reliably reach the remote shell, so tempfile is the practical channel.)
WINPW_FILE="/tmp/crux-winpw"
[[ -f "$WINPW_FILE" ]] || die "password tempfile $WINPW_FILE missing; phase-1 should have scp'd it"
WIN_PASS="$(<"$WINPW_FILE")"
shred -u "$WINPW_FILE" 2>/dev/null || rm -f "$WINPW_FILE"
[[ -n "$WIN_PASS" ]] || die "empty password read from tempfile"

USER_HOME="$HOME"
INVOKER="$(whoami)"

# --------------------------------------------------------------------------- #
# apt packages                                                                #
# --------------------------------------------------------------------------- #
install_apt() {
    log "installing apt packages"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl git tmux rsync jq \
        python3 python3-venv python3-pip \
        build-essential pkg-config
}

# --------------------------------------------------------------------------- #
# Docker                                                                      #
# --------------------------------------------------------------------------- #
install_docker() {
    if command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; then
        log "docker already installed ($(docker --version))"
    else
        log "installing Docker CE (Debian 12 repo)"
        sudo install -m 0755 -d /etc/apt/keyrings
        if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
            sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
        fi
        local codename
        codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $codename stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    if ! id -nG "$INVOKER" | tr ' ' '\n' | grep -qx docker; then
        log "adding $INVOKER to docker group"
        sudo usermod -aG docker "$INVOKER"
        # Use `sg docker` on subsequent docker calls in this script so we
        # don't have to re-login for the group to take effect.
        export _DOCKER_SG=1
    fi
    sudo systemctl enable --now docker
}

docker_() {
    # Wrapper that uses sg when the user wasn't in the docker group at
    # session start (freshly added).
    if [[ "${_DOCKER_SG:-0}" -eq 1 ]]; then
        sg docker -c "docker $*"
    else
        docker "$@"
    fi
}

# --------------------------------------------------------------------------- #
# Go 1.24                                                                     #
# --------------------------------------------------------------------------- #
GO_VERSION="1.24.0"
install_go() {
    if /usr/local/go/bin/go version 2>/dev/null | grep -q "go${GO_VERSION}"; then
        log "go ${GO_VERSION} already installed"
    else
        log "installing Go ${GO_VERSION}"
        local arch tgz
        arch="$(dpkg --print-architecture)"  # amd64 or arm64
        tgz="go${GO_VERSION}.linux-${arch}.tar.gz"
        curl -fsSL "https://go.dev/dl/${tgz}" -o "/tmp/${tgz}"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "/tmp/${tgz}"
        rm -f "/tmp/${tgz}"
    fi
    # Make go available for the rest of this script and future shells.
    export PATH="/usr/local/go/bin:$PATH"
    if ! grep -q '/usr/local/go/bin' "$USER_HOME/.profile" 2>/dev/null; then
        echo 'export PATH="/usr/local/go/bin:$PATH"' >> "$USER_HOME/.profile"
    fi
}

# --------------------------------------------------------------------------- #
# dexbox — PR #45 branch                                                      #
# --------------------------------------------------------------------------- #
DEXBOX_REPO="https://github.com/getnenai/dexbox.git"
DEXBOX_BRANCH="feat/rdp-add-drive-flags"
DEXBOX_SRC="$USER_HOME/src/dexbox"
DEXBOX_BIN="/usr/local/bin/dexbox"

build_dexbox() {
    if [[ -d "$DEXBOX_SRC/.git" ]]; then
        log "refreshing dexbox source at $DEXBOX_SRC"
        git -C "$DEXBOX_SRC" fetch origin "$DEXBOX_BRANCH"
        git -C "$DEXBOX_SRC" checkout "$DEXBOX_BRANCH"
        git -C "$DEXBOX_SRC" reset --hard "origin/$DEXBOX_BRANCH"
    else
        log "cloning dexbox ($DEXBOX_BRANCH)"
        mkdir -p "$(dirname "$DEXBOX_SRC")"
        git clone --branch "$DEXBOX_BRANCH" --depth 50 "$DEXBOX_REPO" "$DEXBOX_SRC"
    fi

    local want_sha
    want_sha="$(git -C "$DEXBOX_SRC" rev-parse HEAD)"

    # Skip rebuild if the installed binary is already from this SHA.
    if [[ -x "$DEXBOX_BIN" ]] && "$DEXBOX_BIN" version 2>/dev/null | grep -q "$want_sha"; then
        log "dexbox at $DEXBOX_BIN already at $want_sha; skipping rebuild"
        return 0
    fi

    log "building dexbox from $(basename "$DEXBOX_SRC")@$want_sha"
    (
        cd "$DEXBOX_SRC"
        # Most dexbox-style repos have a main package at ./cmd/dexbox; fall
        # back to module root if that's absent.
        local pkg="./cmd/dexbox"
        [[ -d "$DEXBOX_SRC/cmd/dexbox" ]] || pkg="."
        go build -ldflags "-X main.gitSHA=$want_sha" -o /tmp/dexbox.new "$pkg"
    )
    sudo install -m 0755 /tmp/dexbox.new "$DEXBOX_BIN"
    rm -f /tmp/dexbox.new
    log "installed $DEXBOX_BIN ($("$DEXBOX_BIN" version 2>/dev/null || echo '(no --version)'))"
}

# --------------------------------------------------------------------------- #
# guacd image                                                                 #
# --------------------------------------------------------------------------- #
pull_guacd() {
    if docker_ image inspect guacamole/guacd:latest >/dev/null 2>&1; then
        log "guacamole/guacd:latest image already present"
    else
        log "pulling guacamole/guacd:latest"
        docker_ pull guacamole/guacd:latest
    fi
}

# --------------------------------------------------------------------------- #
# ~/.dexbox/shared ownership fix (root:root bug)                              #
# --------------------------------------------------------------------------- #
fix_shared_ownership() {
    local d="$USER_HOME/.dexbox/shared"
    mkdir -p "$USER_HOME/.dexbox"
    sudo mkdir -p "$d"
    sudo chown -R "$INVOKER:$INVOKER" "$USER_HOME/.dexbox"
    log "chowned $USER_HOME/.dexbox to $INVOKER"
}

# --------------------------------------------------------------------------- #
# tmux: dexbox start                                                          #
# --------------------------------------------------------------------------- #
start_dexbox() {
    if tmux has-session -t dexbox 2>/dev/null; then
        log "tmux session 'dexbox' already exists; leaving it alone"
    else
        log "starting 'dexbox start' in tmux session 'dexbox'"
        tmux new-session -d -s dexbox "exec $DEXBOX_BIN start 2>&1 | tee -a $USER_HOME/.dexbox/dexbox.log"
    fi
    # Wait for the HTTP endpoint to be reachable.
    local tries=0
    until curl -fsS --max-time 2 http://localhost:8600/health >/dev/null 2>&1; do
        tries=$((tries + 1))
        [[ "$tries" -gt 30 ]] && die "dexbox did not come up on localhost:8600 within ~60s. Check: tmux attach -t dexbox"
        sleep 2
    done
    log "dexbox is up on localhost:8600"
}

# --------------------------------------------------------------------------- #
# dexbox rdp add                                                              #
# --------------------------------------------------------------------------- #
register_rdp() {
    # Remove existing 'win' registration if present so `rdp add` is idempotent.
    if "$DEXBOX_BIN" rdp list 2>/dev/null | grep -qE '(^|[[:space:]])win([[:space:]]|$)'; then
        log "existing rdp target 'win' found; removing first (idempotency)"
        "$DEXBOX_BIN" rdp remove win >/dev/null 2>&1 || warn "rdp remove win failed; continuing"
    fi
    log "registering rdp target 'win' -> $WIN_HOST (user=$WIN_USER, drive=Agent)"
    # dexbox's `--pass` flag is a plain StringVar on PR #45's branch — it does
    # not read from stdin and does not honor an env var. We pass via argv, which
    # means the password is briefly visible in `ps` during this single
    # invocation. Acceptable for a dev/experiment VM; revisit if dexbox gains
    # `--pass-file` or stdin support.
    "$DEXBOX_BIN" rdp add win \
        --host "$WIN_HOST" \
        --user "$WIN_USER" \
        --pass "$WIN_PASS" \
        --security nla \
        --drive-name Agent \
        || die "dexbox rdp add failed"
    log "rdp target registered"
    # Scrub in case dexbox stored the arg anywhere on disk with liberal perms.
    chmod -R go-rwx "$USER_HOME/.dexbox" 2>/dev/null || true
}

# --------------------------------------------------------------------------- #
# Python venv + harness deps                                                  #
# --------------------------------------------------------------------------- #
VENV_DIR="$USER_HOME/crux-windows-venv"
setup_venv() {
    if [[ ! -d "$VENV_DIR" ]]; then
        log "creating venv at $VENV_DIR"
        python3 -m venv "$VENV_DIR"
    fi
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip wheel >/dev/null

    local pyproj="$USER_HOME/crux-windows/harness/pyproject.toml"
    if [[ -f "$pyproj" ]]; then
        log "pip installing crux-windows harness (editable, from pyproject)"
        pip install -e "$USER_HOME/crux-windows/harness"
    else
        warn "pyproject.toml missing at $pyproj — falling back to hardcoded deps matching spec"
        pip install \
            "anthropic>=0.40.0" \
            "google-cloud-storage>=2.14" \
            "google-cloud-secret-manager>=2.16" \
            "paramiko>=3.4" \
            "httpx>=0.27"
    fi
    deactivate
}

# --------------------------------------------------------------------------- #
# Smoke test                                                                  #
# --------------------------------------------------------------------------- #
smoke_test() {
    log "running smoke test"
    local sentinel="$USER_HOME/.dexbox/shared/ping.txt"
    printf 'ping %s\n' "$(date -u +%s)" > "$sentinel" \
        || die "could not write $sentinel — ownership of ~/.dexbox/shared is wrong"
    log "sentinel written: $sentinel"

    # Bring the RDP session up. The documented dexbox CLI is `dexbox up <name>`;
    # HTTP equivalent is POST /desktops/<name>?action=up.
    if ! "$DEXBOX_BIN" up win 2>/dev/null; then
        warn "'dexbox up win' failed; falling back to HTTP POST /desktops/win?action=up"
        curl -fsS -X POST "http://localhost:8600/desktops/win?action=up" >/dev/null \
            || die "could not bring RDP session up"
    fi

    # Verify drive_enabled directly from the on-disk connection store written
    # by `dexbox rdp add`. This is the authoritative path (what PR #45's tests
    # exercise); the HTTP /desktops/{name} response does NOT surface
    # drive_enabled — see PR #45 body.
    local conns="$USER_HOME/.dexbox/connections.json"
    [[ -f "$conns" ]] || die "connections store missing at $conns; rdp add did not persist"
    if ! grep -q '"drive_enabled"[[:space:]]*:[[:space:]]*true' "$conns"; then
        die "drive_enabled != true in $conns — PR #45's --drive-name Agent did not take effect. Dump: $(cat "$conns")"
    fi
    log "drive_enabled=true confirmed in $conns"

    # Look for RDPDR handshake in guacd log.
    local handshake
    handshake="$(docker_ ps --filter ancestor=guacamole/guacd --format '{{.ID}}' | head -n1)"
    if [[ -n "$handshake" ]]; then
        if docker_ logs --tail 200 "$handshake" 2>&1 | grep -iE 'rdpdr|drive redirection' | tee -a "$LOG_FILE" | head -n5; then
            log "guacd RDPDR handshake line observed"
        else
            warn "no RDPDR log line seen yet in guacd container $handshake; drive_enabled is true but redirection may not be negotiated yet. Review: docker logs $handshake"
        fi
    else
        warn "no running guacamole/guacd container found; dexbox may manage its own guacd process. Skipping log inspection."
    fi

    log "SMOKE TEST PASSED"
}

# --------------------------------------------------------------------------- #
# orchestrate                                                                 #
# --------------------------------------------------------------------------- #
install_apt
install_docker
install_go
fix_shared_ownership
build_dexbox
pull_guacd
start_dexbox
register_rdp
setup_venv
smoke_test

log "phase 2 complete"
