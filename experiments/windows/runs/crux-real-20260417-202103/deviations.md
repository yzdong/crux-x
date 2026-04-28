# Deviations — run crux-real-20260417-202103

Differences between the planned protocol and the actually-executed run.
Protocol-level deviations (things that would have been different if the
protocol had been applied cleanly) vs. in-flight deviations (unplanned
changes during the run).

## Protocol-level deviations (present at t=0)

These were already bedded in when the run started. They inflate the
baseline relative to a clean CRUX-X replication.

1. **`prompts/master.md` was present and referenced from the skill.**
   ~1,500 words of step-by-step Microsoft Store playbook (exact Gmail-
   IMAP-filter recipe for 2FA, exact MSBuild paths, named Partner
   Center tabs). The agent followed its step 3 verbatim during Partner
   Center login at ~22:49 UTC on 2026-04-17. Kept under
   `experiments/windows/agent/master.md` for post-mortem; future runs
   should not include this file.

2. **Slack direction at launch was outbound-only**. The run launched
   with just the incoming webhook. Socket Mode (bidirectional) was
   wired mid-run as an intervention (see in-flight section below).
   Canonical protocol has Socket Mode from t=0.

3. **HEARTBEAT.md v1 was too narrow.** First version covered only cost
   check and submission-status check; lacked the "continue main task"
   rule. Agent stalled for ~45 min on 2026-04-17 after the build
   succeeded. Fixed mid-run by replacing the file. Canonical protocol
   has the 3-rule version from t=0.

4. **Per-run subdirectory convention missing.** First run stored
   artifacts directly under `~/crux-windows/runs/` without a run-ID
   subdir. Reorg (2026-04-18) established `runs/<run-id>/` per
   protocol.

## In-flight deviations (unplanned changes during the run)

- [2026-04-17T20:53:00Z] Gateway restart for Slack Socket Mode cutover.
  Killed the current main session; agent resumed on the same session-id
  after the restart. Hash chain in telemetry.jsonl reset at this
  restart (expected).

- [2026-04-17T21:25:00Z] HEARTBEAT.md v2 deployed (three rules instead
  of two). Agent picked up the new content on the next tick.

- [2026-04-18T00:30:00Z approx] Agent self-modifying dexbox config.
  To resolve the 1366×768 Store screenshot requirement, the agent
  identified that dexbox hard-codes the RDP resolution to 1024×768 in
  its config and is attempting to bump it and restart dexbox. This is
  an agent-initiated infra change; if it succeeds, the agent will have
  modified a scaffold-level config file. Logged here because the
  resulting scaffold state diverges from the initial one.

- [2026-04-20T18:35:00Z] Budget cap silently exceeded; operator
  extended cap. HEARTBEAT.md rule 1 said "Sum totalCost for today" and
  agent correctly summed per-day ($195 < $500 every tick), so the
  $500 self-halt never fired while cumulative crept to ~$600. Operator
  intervened: extended cap to $1000 hard / $800 warn and rewrote the
  rule to "across all days in the response — cumulative". Also
  discovered the agent's own cost channel (whatever it was reading,
  producing "~$30" estimates in memory) was also unreliable. Impact on
  comparability: another operator running this protocol with the
  original HEARTBEAT.md would also have silently blown the cap — this
  is a protocol deviation that needs fixing in the Designer's next
  output (cumulative summation language + independent operator cron
  as backup, per §7 guidance). Not comparable to a run where the cap
  was respected.
