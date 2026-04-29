#!/usr/bin/env bash
# provision_vm.sh — create the CRUX-Land controller VM in GCE.
#
# Runs from the operator's laptop. Idempotent — re-running on an existing
# VM is a no-op (gcloud will report "already exists" and we exit cleanly).
#
# After creating the VM, this script SCPs the repo to the VM and invokes
# provision_controller.sh ON the VM via IAP SSH. End state: a controller
# ready for `bash preflight.sh`.
#
# Usage:
#   bash provision_vm.sh
#
# Prereqs:
#   - gcloud auth refreshed (`gcloud auth login`)
#   - PROJECT, ZONE, VM_NAME exported in env (or set via per-run manifest's
#     "Resolved infra" section; see manifest-template.md). Defaults below
#     are placeholders that will fail fast if not overridden.

set -euo pipefail

PROJECT="${PROJECT:-}"
ZONE="${ZONE:-us-central1-a}"
VM_NAME="${VM_NAME:-${CONTROLLER_VM:-crux-land-ctrl}}"
MACHINE_TYPE="${MACHINE_TYPE:-n2-standard-8}"
DISK_SIZE_GB=100
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"
NETWORK_TAG="crux-land"
SERVICE_ACCOUNT_SCOPES="cloud-platform"  # for gsutil archiving from the VM

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { printf '[%s] %s\n' "$(ts)" "$*" ; }

# 1. Sanity: project + auth
if [ -z "$PROJECT" ]; then
  echo "ERROR: PROJECT not set. Export PROJECT=<your-gcp-project-id> (also record in manifest:infra.gcp_project)." >&2
  exit 1
fi

ACTIVE_PROJECT="$(gcloud config get-value project 2>/dev/null)"
if [ "$ACTIVE_PROJECT" != "$PROJECT" ]; then
  log "switching active project: ${ACTIVE_PROJECT} -> ${PROJECT}"
  gcloud config set project "$PROJECT"
fi

if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q '@' ; then
  echo "ERROR: no active gcloud auth. Run: gcloud auth login" >&2
  exit 1
fi

# 2. Create the VM if absent
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  log "VM ${VM_NAME} already exists in ${ZONE}; skipping create"
else
  log "creating VM ${VM_NAME} (${MACHINE_TYPE}, ${DISK_SIZE_GB}G, ${IMAGE_FAMILY}) in ${ZONE}"
  gcloud compute instances create "$VM_NAME" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --boot-disk-size="${DISK_SIZE_GB}GB" \
    --boot-disk-type="pd-ssd" \
    --tags="$NETWORK_TAG" \
    --scopes="$SERVICE_ACCOUNT_SCOPES" \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring
  # Note: VM gets a public IP by default. The project does not have
  # Cloud NAT configured; CRUX-Windows used the same public-IP shape.
  # Inbound is still IAP-only via the allow-iap-ssh firewall rule
  # (35.235.240.0/20 -> tcp:22).
fi

# 4. Wait for SSH-readiness (instance can take a minute to be reachable).
log "waiting for IAP SSH to come up on ${VM_NAME}"
deadline=$(( $(date +%s) + 180 ))
until gcloud compute ssh "$VM_NAME" \
        --zone="$ZONE" \
        --tunnel-through-iap \
        --command='echo OK' >/dev/null 2>&1; do
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo "ERROR: SSH did not come up within 180s." >&2
    exit 1
  fi
  sleep 5
done
log "SSH up"

# 5. Push the experiment repo to the VM
REPO_LOCAL="$(cd "$(dirname "$0")/../../.." && pwd)"
log "syncing repo from ${REPO_LOCAL} to ${VM_NAME}:~/crux-land/"
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --tunnel-through-iap \
  --command='mkdir -p ~/crux-land' >/dev/null

gcloud compute scp \
  --zone="$ZONE" \
  --tunnel-through-iap \
  --recurse \
  "${REPO_LOCAL}/methodology.md" \
  "${REPO_LOCAL}/README.md" \
  "${REPO_LOCAL}/experiments" \
  "${VM_NAME}:~/crux-land/"

# 6. Run controller bootstrap on the VM
log "running provision_controller.sh on ${VM_NAME}"
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --tunnel-through-iap \
  --command='bash ~/crux-land/experiments/land/scripts/provision_controller.sh'

log "provision_vm.sh complete"
log "next: provision external accounts per experiments/land/scripts/USER-CHECKLIST.md"
log "      then run preflight: gcloud compute ssh ${VM_NAME} --tunnel-through-iap --zone=${ZONE} -- bash ~/crux-land/experiments/land/scripts/preflight.sh"
