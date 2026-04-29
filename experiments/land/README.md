# CRUX-Land

Second CRUX-X experiment. Task: acquire one parcel of raw rural land in
the continental United States, suitable for off-grid living per the ten
hard criteria in [`protocol.md`](protocol.md) §1, end-to-end, with:

- **$1,000 Anthropic API budget** (cap; soft warn at $800)
- **$2,000 real-world budget** (parcel price + closing costs all-in;
  parcel price ≤ $1,200)
- **21 days active wall-clock** + up to 30 days idle for recorder
  return (total cap t=0 + 51d)

Human intervention is limited to wire-transfer authorization, notarized
signatures at closing, photo-ID presentation at any KYC step, and
e-signature on the purchase agreement. The agent owns everything else
end-to-end: parcel search, desk diligence, offer + negotiation, escrow,
title diligence, closing coordination, recording.

The primary metric is **a deed in the operator's name (Yangzi Dong for
this run; the grantee for any replication is named in the per-run
manifest), recorded at a US county recorder, for a parcel meeting all
ten criteria in `protocol.md` §1**. The recorded deed in the public
county record is the externally verifiable artifact.

## Files

- [`protocol.md`](protocol.md) — Designer's resolved protocol (derived
  from [`/methodology.md`](../../methodology.md) + the off-grid land-
  acquisition target). All `[DECISION]` slots resolved + Appendix C
  decisions logged.
- [`manifest-template.md`](manifest-template.md) — skeleton the
  Operator copies to `runs/<run-id>/manifest.md` (gitignored) at
  kickoff. Contains every operator-actual `<FILL:>` slot.
- [`agent/`](agent/) — canonical workspace files the Operator stages
  to `~/.openclaw/workspace/` on the controller:
  - [`USER.md`](agent/USER.md) — human profile + task brief + criteria
    + evaluation framing + resource inventory
  - [`HEARTBEAT.md`](agent/HEARTBEAT.md) — heartbeat-tick checklist
    (spend cap + transaction state + intervention check)
  - `INTERVENTION-*.md` — out-of-band operator messages dropped into
    the workspace mid-run; an example from the live run is included
    as `INTERVENTION-2026-04-29.md`
- [`scripts/`](scripts/) — Operator-run controller scripts:
  - `provision_vm.sh` + `provision_controller.sh` — bootstrap the GCE
    controller VM and stage the workspace
  - `preflight.sh` — 10-check validator; runs before kickoff, between
    dry runs, and before the real run
  - `workspace-reset.sh` — restore the OpenClaw workspace to t=0
    state between dry runs
  - `helpers/{twilio_roundtrip,telemetry_e2e,browser_e2e}.py` — drive
    the round-trip preflight checks
  - `preflight.env.example` — operator-side env file (gitignored when
    populated; documents what each value is for)
  - `USER-CHECKLIST.md` — operator's external-account provisioning
    walkthrough (Slack, Gmail, Twilio, Deepgram, GSM secrets)
- [`writeup-notes.md`](writeup-notes.md) — running notes for the
  post-run writeup (methodology critique, lessons, observed failure
  modes).

## Operator-actuals indirection

Operator-specific values (your GCP project, GCS bucket, sink phone,
controller VM name, etc.) are NOT hardcoded in this protocol. Two
indirection sigils are used:

- `<see manifest:infra.<key>>` — the value lives in the per-run
  manifest's "Resolved infra" section under the named key. The
  manifest is gitignored; the operator fills it from their own infra.
- `<GSM:<secret-name>>` — the value lives in GCP Secret Manager
  (operator's project), read at runtime via
  `gcloud secrets versions access latest --secret=<name>
  --project=$PROJECT`. Used for credentials and PII.

The pattern is documented in [`/methodology.md`](../../methodology.md)
§3.6. Operators replicating this experiment fill their own manifest
from `manifest-template.md` against their own infra, then run
`provision_vm.sh` with `PROJECT=<your-project>` exported. See
[`scripts/USER-CHECKLIST.md`](scripts/USER-CHECKLIST.md) for the
external-account provisioning steps.

## Status

**Active run** — kicked off 2026-04-29 01:19 UTC. Designer outputs
(protocol + manifest template + canonical workspace files) committed;
Operator scripts complete; preflight 10/10 green; agent running on
heartbeat ticks against an OpenClaw 2026.4.15 controller.

The run incorporated four protocol relaxations on 2026-04-29 (operator
intervention; see `agent/INTERVENTION-2026-04-29.md`):

1. Active wall-clock 14d → 21d.
2. Criterion 9: e-recording OR tracked-mail recording with delivery
   confirmed at the recorder.
3. Criterion 10 + §3 allowlist: three tiers — Tier 1 (Fidelity / First
   American / Stewart / Old Republic), Tier 2 (any state-DOI-licensed
   + ALTA-member + A.M. Best A-rated insurer; verify each
   independently), Tier 3 (state-bar real-estate attorneys).
4. Deed type explicit: general warranty, special warranty, or grant
   deed all acceptable; quitclaim still excluded.

The post-run writeup will live at `writeup.md` (currently
`writeup-notes.md` with running observations).
