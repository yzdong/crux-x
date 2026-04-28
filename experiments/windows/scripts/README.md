# CRUX-Windows scripts

## Provisioning the controller

`provision_controller.sh` stands up a fresh Debian 12 controller VM in GCE and
wires it to a pre-existing Windows target VM. After it succeeds, the VM has
Go 1.24, Docker, Python 3.11, tmux, rsync; dexbox built from PR #45's branch
(`feat/rdp-add-drive-flags`); guacd pulled; the harness venv populated from
`harness/pyproject.toml`; `dexbox start` running in tmux; an RDP target
registered with `--drive-name Agent`; and a smoke test has confirmed
`drive_enabled: true`.

Prereqs (local Mac):

- `gcloud auth login && gcloud auth application-default login`
- rsync, ssh (come with macOS)
- The Windows target VM already exists in the same project/zone and is RUNNING

One-line invocation (you'll be prompted for the Windows password silently):

```bash
CRUX_WIN_NAME=crux-win-01 ./provision_controller.sh
```

Dry-run (prints every gcloud command it would invoke; no state changes, no
auth required):

```bash
./provision_controller.sh --win-name crux-win-01 --dry-run
```

All flags: `--project`, `--zone`, `--ctrl-name`, `--win-name` (required),
`--win-user`, `--local-src`, `--dry-run`, `--use-secret-manager` (read
`crux-windows-target-pass` secret instead of prompting).

Logs tee to `/tmp/crux-provision.log` on both sides. IAP tunneling is used
for every SSH/SCP/rsync hop. Re-running is idempotent; each step is guarded
by an existence or version check.

Teardown: `gcloud compute instances delete $CRUX_CTRL_NAME --zone=us-central1-a --project=<your-gcp-project>`. The Windows target VM is intentionally left alone.

## CRUX-Windows credential staging

`stage_creds.py` pulls experiment secrets from GCP Secret Manager (project
`<your-gcp-project>`) and writes a single JSON file the agent harness reads at
startup: `~/.dexbox/shared/creds.json` (mode `0600`).

## Prereqs

```bash
pip install -r requirements.txt
gcloud auth application-default login
```

The script prefers the `google-cloud-secret-manager` SDK but falls back to
`gcloud secrets versions access` if the SDK isn't importable, so a bare VM
with just `gcloud` still works.

## One-time secret setup

Create the secrets once (the `|| echo` clause makes this idempotent — re-runs against an existing secret are no-ops). `slack-crux-windows` is already populated and listed here so the loop is complete.

```bash
PROJECT=<your-gcp-project>
SECRETS=(
  microsoft-email microsoft-password
  partner-center-login partner-center-password
  github-email github-pat
  gmail-email gmail-app-password
  twilio-account-sid twilio-auth-token twilio-phone-number
  support-phone support-email
)
for s in "${SECRETS[@]}"; do
  gcloud secrets create "$s" \
    --project="$PROJECT" \
    --replication-policy=automatic || echo "  (already exists: $s)"
done
```

Then populate each one:

```bash
printf '%s' 'the-value' | gcloud secrets versions add <name> \
  --project="$PROJECT" --data-file=-
```

## Usage

```bash
./stage_creds.py              # fetch + write creds.json
./stage_creds.py --dry-run    # list planned fetches, don't call GCP
```

On success it prints the output path and a summary of which keys are present
vs. missing (missing secrets are written as `"__MISSING__"`; the run does not
abort).

## Notes

- The script chowns `~/.dexbox/shared/` back to the invoking user via `sudo`
  before writing — works around a `dexbox start` bug where that directory is
  created as `root:root`. Idempotent.
- Re-running overwrites `creds.json` atomically.
- To add/rename a secret: edit the `SECRETS` dict at the top of
  `stage_creds.py` (JSON key -> Secret Manager name).
