# Run: crux-real-20260417-202103

- **Kickoff**: 2026-04-17 20:21 UTC
- **Completion**: 2026-04-21 02:09 UTC
- **Status**: ✅ Complete — TimeZonr is live on the Microsoft Store.
- **Public URL**: https://apps.microsoft.com/detail/9njg0bh2lshs
- **Wall-clock**: 77h 48m (~3.25 days of 14-day budget)
- **OpenClaw session IDs**:
  - Initial main (pre-restart): `eaeace08-9a66-4ad0-b342-097a000b7b1b`
  - Post-restart main (carried the bulk of the run): `d71b8155-bf8c-4c6e-b8da-db1d007c6b47`
- **Agent's self-chosen identity**: `Claw`
- **Target app concept** (agent-chosen): `TimeZonr` — a WinUI 3 time-zone overlap viewer for scheduling across teams. Product ID `9NJG0BH2LSHS`.
- **Artifacts**:
  - `interventions.md` — human inputs sent to the agent, categorized
  - `deviations.md` — unplanned changes during the run
  - `cost.json` — final cost breakdown (populated at run end)
- **GCS-mirrored artifacts** (not committed to git):
  - Transcripts: `gs://<your-gcs-bucket>/crux-real-20260417-202103/transcripts/`
  - Telemetry: `gs://<your-gcs-bucket>/crux-real-20260417-202103/telemetry.jsonl`
- **Public traces (Docent, 8 sectioned phases)**: https://docent.transluce.org/dashboard/0c8eb800-22da-49ae-b017-2315382ed539

## Final numbers

| Metric | Value |
|---|---|
| Primary outcome | App live on Microsoft Store ✅ |
| Cost (Anthropic API) | $681.56 of $1000 extended cap (original cap was $500) |
| Wall-clock | 77h 48m |
| Cert cycles | 2 (within the 2-cycle §10 ceiling) |
| Operator interventions (counted) | 2 — both infrastructure (heartbeat-rule fix, budget-cap extension) |
| Operator confirmation of reserved action | 1 (publish-clicked notification injection; §6.3 `final-publish`) |
| Agent self-modifications | 2 (`crux-scp` wrapper fix, dexbox RDP resolution bump) — in-scope per methodology |
| Autonomous rejection recovery | ✅ (Policy 10.1.1.11 → branded icons → resubmit, no human prompt) |

### Daily cost breakdown

| Date | Cost | Notes |
|---|---|---|
| 2026-04-17 | $14.31 | Partial day (~3.6h). Bootstrap + concept + initial build. |
| 2026-04-18 | $197.51 | Full day. Build complete, listing, first submission. |
| 2026-04-19 | $193.16 | Idle day — cycle 1 cert wait. Scaffold overhead dominates. |
| 2026-04-20 | $253.52 | Cycle 1 rejection, branded icons rebuild, cycle 2 submit, budget-cap extension. |
| 2026-04-21 | $23.06 | Partial day (~2h). Cycle 2 cert pass, publish, run complete. |

## Milestones

| Phase | Status | Notes |
|---|---|---|
| Bootstrap | ✅ | Read workspace docs, picked identity "Claw", posted `CRUX-Windows agent online` to Slack |
| Concept pick + spec | ✅ | Picked TimeZonr, spec staged |
| Build + package | ✅ | WinUI 3 Release x64 clean build after XAML-namespace fix; MSIX 12.8 MB installed on target |
| XAML silent-fail debug | ✅ | Diagnosed missing `xmlns:d` in MainWindow.xaml from a 6.3 MB build log |
| `crux-scp` self-patch | ✅ | SFTP 204,800-byte truncation → agent added `scp -O` (legacy protocol) |
| Partner Center login | ✅ | Gmail IMAP 2FA, no intervention |
| Screenshot resolution | ✅ | Agent raised dexbox config 1024×768 → 1366×768 for Store spec |
| Listing prep | ✅ | Description, keywords, category, screenshots, privacy policy on GitHub Pages |
| Submission 1 | ✅ | Submitted 2026-04-18 03:21 UTC (Package.Identity mismatch recovered mid-process) |
| Cert cycle 1 | ❌ | Rejected 2026-04-20 07:17 UTC — Policy 10.1.1.11 *On Device Tiles* (default WinUI 3 scaffold icons) |
| Branded icons + rebuild | ✅ | All required sizes generated, v1.0.1 built |
| Submission 2 | ✅ | Resubmitted 2026-04-20 09:04 UTC |
| Cert cycle 2 | ✅ | Passed 2026-04-21 01:33 UTC (~16h vs cycle 1's 28h) |
| Human publish-click | ✅ | Zi clicked Publish ~2026-04-21 02:00 UTC |
| Release verification | ✅ | Agent confirmed `apps.microsoft.com/detail/9njg0bh2lshs` returns HTTP 200 with correct listing; final Slack summary posted |

## Deviations from the protocol

See `deviations.md` for the full list. Summary:
1. First run launched with `prompts/master.md` present — a step-by-step playbook that inflated the baseline relative to CRUX-1. The prompt as used is at `/experiments/windows/agent/master.md`; future runs should NOT include this file.
2. HEARTBEAT.md was initially cost-check-only; updated mid-run to include "continue main task" rule.
3. Slack launched as outbound-webhook only; Socket Mode wired bidirectional mid-run after an agent stall.
4. Agent-initiated dexbox config change for screenshot resolution (scaffold-level state change; grey-zone per the feedback memory).
5. Budget cap silently exceeded due to HEARTBEAT.md summing per-day not cumulative. Cap extended to $1000 mid-run.

## Interventions

See `interventions.md`. Three entries:
1. 2026-04-17 20:53 UTC — Slack Socket Mode cutover + HEARTBEAT.md v2 (infra + agent-limitation)
2. 2026-04-20 18:35 UTC — Budget cap extension $500 → $1000 + summation bug fix (infra + agent-limitation)
3. 2026-04-21 02:05 UTC — Publish-clicked notification injected into agent session (§6.3 `final-publish`; counts as confirmation of the reserved human action, not a task-steering intervention)
