# CRUX-Land scripts

Operator-side scripts. All run on the controller VM (`crux-land-ctrl`).

## Contents

- `preflight.sh` — validator for all 10 checks in `protocol.md` §8.
  Run before every dry run and before the real run. Exits 0 on full
  pass, 1 on first failure with an actionable hint. Mostly read-only;
  checks 10/11/12 each trigger one real round-trip (dummy tool call,
  outbound Twilio call, browser navigate) to validate end-to-end
  pipelines without mutating experiment state.
- `workspace-reset.sh` — restores the OpenClaw workspace to its
  canonical t=0 state (stock templates + the canonical `USER.md` /
  `HEARTBEAT.md` from `experiments/land/agent/`). Run between dry
  runs and before the real run, per protocol §8.
- `stage-workspace.sh` — copies `experiments/land/agent/USER.md` and
  `HEARTBEAT.md` to `~/.openclaw/workspace/`. Used by `workspace-reset.sh`
  internally and standalone if you only want to refresh those two
  files.
- `helpers/twilio_roundtrip.py` — places a test outbound call from
  the provisioned Twilio number to a sink phone, fetches the
  recording, and transcribes it. Invoked by `preflight.sh` check 11.
- `helpers/telemetry_e2e.py` — triggers a dummy tool invocation and
  verifies both `tool.*` AND `agent.usage` events appear in
  `telemetry.jsonl`. Invoked by `preflight.sh` check 10.
- `helpers/browser_e2e.py` — triggers a real `browser` navigate +
  screenshot through the gateway and verifies a non-empty trace
  directory landed at `~/.openclaw/logs/browser-traces/<call-sid>/`
  (with `trace.cdp.json`, `trace.network.json`, and at least one
  screenshot), AND that the corresponding `tool.end` event in
  `telemetry.jsonl` carries a `browserTracePath` field. Invoked by
  `preflight.sh` check 12. Closes the silent-recording-loss failure
  mode (the analogue of the silent-telemetry-loss bug from
  CRUX-Windows).
- `requirements.txt` — Python dependencies (twilio, deepgram-sdk for
  transcription, etc.).

## Environment

`preflight.sh` reads from `~/.crux-land/preflight.env` (sourced if
present) or falls back to defaults. Required variables:

```sh
# ~/.crux-land/preflight.env
SINK_PHONE_NUMBER=+1XXXXXXXXXX        # operator's phone for Twilio test
SINK_EMAIL_ADDRESS=ops-sink@example.com  # operator-owned auto-reply
```

The script will tell you which variable is missing if you run it
without these set.

## Order of operations

1. Provision GCP project + bucket (one-time).
2. Provision external accounts (Gmail, Twilio, Slack channel,
   Deepgram) per protocol §3 (one-time).
3. Populate GCP Secret Manager secrets per `USER-CHECKLIST.md` (one-time).
4. Stand up controller VM via `provision_controller.sh` (TBD).
5. `bash preflight.sh` — until 10/10 green.
6. `bash workspace-reset.sh` — clean slate.
7. Run dry-run smoke 1 (tool wiring + browser navigate/screenshot).
8. `bash workspace-reset.sh`.
9. Run dry-run smoke 2 (counterparty email round-trip).
10. `bash workspace-reset.sh`.
11. `bash preflight.sh` — re-confirm 10/10 green.
12. Populate `runs/<run-id>/manifest.md` from `manifest-template.md`.
13. Send the bootstrap message: `Read AGENTS.md and get started.`
