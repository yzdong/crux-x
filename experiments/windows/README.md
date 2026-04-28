# CRUX-Windows

First CRUX-X experiment. Task: publish a simple Windows desktop
application to the Microsoft Store, end-to-end, with a $500 Anthropic
API budget and 14 days of wall-clock. Human intervention limited to
Microsoft developer account biometric ID verification (pre-done) and
the final "publish live" click.

## Files

- [`protocol.md`](protocol.md) — the Designer's resolved protocol
  (derived from `/methodology.md` + the target-task description).
- [`evaluation.md`](evaluation.md) — Designer-vs-actual comparison,
  used to identify methodology gaps.
- [`dry-runs/`](dry-runs/) — artifacts from bounded smoke runs before
  real-run launches.
- [`agent/`](agent/) — canonical workspace files the Operator stages to
  the OpenClaw workspace on the controller (`~/.openclaw/workspace/`):
  - [`USER.md`](agent/USER.md) — human profile + task brief +
    evaluation framing + resources
  - [`HEARTBEAT.md`](agent/HEARTBEAT.md) — three-rule tick checklist
    (cost check, submission status, continue main task)
  - [`skills/crux-windows/SKILL.md`](agent/skills/crux-windows/SKILL.md)
    — OpenClaw skill descriptor registering the `crux-dexbox` + `crux-ssh`
    wrappers
- [`scripts/`](scripts/) — Operator-run provisioning + preflight +
  Windows-specific tool wrappers. The two wrappers (`crux-dexbox`,
  `crux-ssh`) are deployed to `/usr/local/bin/` on the controller.
- [`runs/`](runs/) — one subdirectory per real run, with `manifest.md`
  (t=0 snapshot), `journal.md` (interventions + deviations combined,
  appended during the run), cost ledger, and pointers to the
  GCS-mirrored transcripts + telemetry.

## Runs

| Run ID | Started | Status | Notes |
|---|---|---|---|
| [`crux-real-20260417-202103`](runs/crux-real-20260417-202103/) | 2026-04-17 20:21 UTC | Active | First real run. Known deviations logged |
