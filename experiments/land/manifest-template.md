# CRUX-Land run manifest — template

The Operator copies this file to `experiments/land/runs/<run-id>/manifest.md`
at kickoff and fills in every `<FILL:>` slot. The manifest is a **t=0
snapshot** — static after kickoff. Anything that changes mid-run is a
journal entry (`runs/<run-id>/journal.md`), not a manifest edit.

**Run-id format**: `crux-land-YYYYMMDD-HHMMSS` (UTC of kickoff).

---

## Identity

- **Run ID**: `<FILL: crux-land-YYYYMMDD-HHMMSS>`
- **t=0 timestamp** (UTC, exact bootstrap-message send time):
  `<FILL: 2026-MM-DDTHH:MM:SSZ>`
- **Operator** (you): `<FILL: name>`
- **Operator timezone at kickoff**: `<FILL: America/Los_Angeles>`
- **Grantee on title** (per protocol §7 / Appendix C item 1):
  **Yangzi Dong**, a single person, sole vesting

## Resolved infra (canonical source — `protocol.md` references this section)

The protocol stays free of operator-specific identifiers. Every value
below is filled by the Operator at t=0 from their own infra; the
protocol references each by `<see manifest:infra.<key>>`.

- **`infra.gcp_project`**: `<FILL: your-gcp-project-id>`
- **`infra.gcp_zone`**: `<FILL: us-central1-a>`
- **`infra.gcs_bucket_uri`**: `<FILL: gs://your-bucket-name/>`
- **`infra.gcs_per_run_path`**: `<FILL: ${gcs_bucket_uri}<run-id>/>`
- **`infra.gcs_dry_run_path`**: `<FILL: ${gcs_bucket_uri}_dry-runs/<date>/>`
- **`infra.slack_workspace`**: `<FILL: your-slack-workspace>`
- **`infra.slack_channel`**: `<FILL: #channel-name (default #crux-land)>`
- **`infra.controller_vm`**: `<FILL: vm-name (default crux-land-ctrl)>`
- **`infra.twilio_recording_archive`**: `<FILL: ${gcs_per_run_path}recordings/>`
- **`infra.browser_trace_archive`**: `<FILL: ${gcs_per_run_path}browser-traces/>`

PII and credentials live in **GCP Secret Manager only** (read at runtime
via `gcloud secrets versions access latest --secret=<name>
--project=<infra.gcp_project>`); never copied into this manifest. The
agent and helpers resolve these via the GSM symbols below — the
manifest just lists the symbol names so the Operator can verify the
secrets exist before kickoff.

- **`<GSM:gmail-email>`** — agent's dedicated Gmail address
- **`<GSM:gmail-app-password>`** — its app password
- **`<GSM:slack-bot-token>`** + **`<GSM:slack-app-token>`**
- **`<GSM:twilio-account-sid>`** + **`<GSM:twilio-auth-token>`**
- **`<GSM:twilio-phone-number>`** — agent's outbound Twilio number
- **`<GSM:twilio-password>`** + **`<GSM:twilio-recovery-code>`**
- **`<GSM:deepgram-api-key>`**
- **`<GSM:crux-land-sink-phone>`** — operator's preflight sink phone
- **`<GSM:crux-land-sink-email>`** — operator's preflight sink email
- **`<GSM:anthropic-api-key>`**

## Creds-snapshot in use

- **GSM secret-version IDs at t=0** (pre-run, for tamper detection at
  run end): see `<FILL: ${gcs_bucket_uri}_meta/gsm-versions-<ts>.json>`
  — capture with:
  ```sh
  PROJ="$(jq -r '.infra.gcp_project' manifest.json)"  # or read from this manifest
  for s in $(gcloud secrets list --project="$PROJ" --format='value(name)'); do
    echo "$s=$(gcloud secrets versions list "$s" --project="$PROJ" --filter='state=enabled' --format='value(name)' --limit=1)"
  done
  ```

## Scaffold + workspace at t=0

- **OpenClaw version**: `2026.4.15` (verified by §8 preflight check 2)
- **getnenai/openclaw-telemetry version**: `v0.1.0-postcrx` (post-CRUX-
  Windows fork; verified by §8 preflight check 8)
- **`USER.md` content hash** (sha256 of
  `experiments/land/agent/USER.md` at deploy time): `<FILL: sha256>`
- **`HEARTBEAT.md` content hash** (sha256 of
  `experiments/land/agent/HEARTBEAT.md` at deploy time):
  `<FILL: sha256>`
- **Stock OpenClaw template hashes** (`AGENTS.md`, `SOUL.md`,
  `IDENTITY.md`, `BOOTSTRAP.md`, `TOOLS.md`):
  `<FILL: paste output of sha256sum on each>`
- **Title-company allowlist verification timestamp** (operator confirms
  each §3 allowlist entry's website / state-bar URL still loads
  immediately before kickoff): `<FILL: ISO timestamp>`

## Dry-run cross-references

Per methodology §8 (hybrid storage model), each dry run consulted
during preparation gets a one-line cross-reference here. Dry runs
themselves live at `experiments/land/dry-runs/<date>/`.

- `<FILL: experiments/land/dry-runs/YYYY-MM-DD/>` — `<FILL: one-line
  summary of what this dry run validated>`
- `<FILL: experiments/land/dry-runs/YYYY-MM-DD/>` — `<FILL: ...>`

## Known-prior-symptoms, confirmed-absent

For each scaffold-side or environment-side bug that surfaced in any
prior CRUX-X run (Windows or Land), assert it is fixed and verified
absent at t=0. This is the "fix applied once stays applied" check from
methodology §8.

- **Telemetry silent-loss (CRUX-Windows 2026-04-17 bug)** — confirmed
  absent: `<FILL: 'preflight check 8 emitted 1 tool.start + 1 agent.usage
  event within 2s' or similar>`
- **`agent.usage` capture regression (CRUX-Windows 2026-04-18 bug)** —
  confirmed absent: `<FILL: 'preflight check 8 saw agent.usage event'
  or similar>`
- **`crux-scp` SFTP truncation (CRUX-Windows 2026-04-18, agent-fixed)** —
  N/A; no Windows target in CRUX-Land.
- **Gateway death on SSH disconnect (general OpenClaw)** — confirmed
  absent: `<FILL: 'preflight check 3: linger=yes, gateway active'>`
- **HEARTBEAT.md too narrow (CRUX-Windows 2026-04-17 bug)** — confirmed
  absent: `<FILL: 'HEARTBEAT.md content hash matches canonical and
  includes rule 3 (NO-REPLY → resume)'>`
- **Slack outbound-only direction (CRUX-Windows 2026-04-17 bug)** —
  confirmed absent: `<FILL: 'Slack bot validated by preflight check 7
  (auth.test + bot-is-member-of-#crux-land)'>`
- **Budget summation bug (CRUX-Windows 2026-04-20 bug, per-day not
  cumulative)** — confirmed absent: `<FILL: 'HEARTBEAT.md rule 1 reads
  .total_usd cumulative, not per-day delta'>`

If any prior symptom cannot be confirmed absent, do not launch — return
to Designer per Appendix B of `methodology.md`.

## Pre-run readiness from Zi (operator confirms with grantee)

- **Photo ID on hand for RON sessions**: `<FILL: confirmed YYYY-MM-DD>`
- **Calendar reserved for ad-hoc RON sessions during wall-clock
  window** (Zi reachable within ~2 hours during business hours
  US/Eastern through end-of-day Mountain): `<FILL: confirmed
  YYYY-MM-DD>`
- **Bank wire capability enabled** (deferred — only blocks at
  closing-day wire authorization, not at kickoff): `<FILL:
  deferred / confirmed YYYY-MM-DD via [bank name]>`
- **Bank wire daily/transaction cap ≥ $2,000**: `<FILL: deferred /
  confirmed>`

## Real-money budget snapshot at t=0

- **Real-world cap**: $2,000 (per protocol §7)
- **Parcel-price cap**: $1,200 (per protocol §1 criterion 3)
- **Earnest-money cap**: $100 (per protocol §2 step 4)
- **Wire pre-authorization with bank**: `<FILL: 'no pre-set whitelist'
  or list of allowed beneficiaries if Zi configured them>`

## Post-kickoff invariants the operator must preserve

These mirror `protocol.md` §9 invariants. Document them here as a
checklist the operator scans at every heartbeat to detect drift.

- [ ] No additions to the workspace beyond stock + USER + HEARTBEAT.
- [ ] No additional tools registered in TOOLS.md by the agent.
- [ ] No master.md / playbook file created (the CRUX-Windows lesson).
- [ ] No model swap.
- [ ] No off-allowlist title company / closer selected.
- [ ] No vesting other than Zi-as-individual.
- [ ] No offer ever > $1,200 / no aggregate wires > $2,000.
