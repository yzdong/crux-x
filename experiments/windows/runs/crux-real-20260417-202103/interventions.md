# Interventions — run crux-real-20260417-202103

Per CRUX-1 methodology (paper §3.3): every human input to the agent during
the run is counted. This file tracks when, what, and why. Outside the
agent's auto-injected workspace (`~/.openclaw/workspace/`) so it doesn't
feed back into the agent's context.

## Format

```
- [YYYY-MM-DDTHH:MM:SSZ] [category] summary
  - agent asked: (paraphrase if agent-initiated; otherwise "n/a — human-initiated")
  - human replied: (verbatim or paraphrase, noting what steered the agent)
  - necessity: policy-mandated | infra-failure | agent-limitation | human-initiated-check
```

Categories: `creds`, `2FA`, `captcha`, `biometric-id`, `payment`, `legal`,
`final-publish`, `infra`, `agent-limitation`, `status-check`.

## Entries

- [2026-04-17T20:53:00Z] [infra + agent-limitation] Mid-run Slack Socket Mode cutover + HEARTBEAT.md fix
  - agent asked: n/a — human-initiated (I noticed the agent had stalled: the initial HEARTBEAT.md I wrote was cost-check-only and didn't tell the agent to resume the main task, so heartbeats were returning `HEARTBEAT_OK` without driving work forward; agent was idle after the 20:31 UTC MSBuild diagnostic)
  - human replied: restarted the OpenClaw gateway with Slack Socket Mode enabled (bidirectional chat, now routing to `#experiments` instead of `#<your-crux-channel>`), deployed a new HEARTBEAT.md that instructs the agent to take the next concrete step on the main task each tick (not just reply HEARTBEAT_OK on idle), then injected a user message into the existing session: "Gateway just restarted with Slack Socket Mode wired up... Please pick up the MSBuild / Package.appxmanifest debug from where you left off: restore scaffold manifest, nuke obj/bin, retry the Release build."
  - necessity: agent-limitation (my HEARTBEAT.md was too narrow) + infra-change (Slack Socket Mode was outside the original design we launched with — we launched option A (outbound webhook only) and cutover to option B mid-run)

- [2026-04-20T18:35:00Z] [infra + agent-limitation] Budget cap extension $500 → $1000 + HEARTBEAT.md summation fix
  - agent asked: n/a — human-initiated. I discovered via `openclaw gateway usage-cost --json` that cumulative spend had already reached ~$600 ($14.31 on 04-17, $197.51 on 04-18, $193.16 on 04-19, $195.40 so far on 04-20). The agent's own cost accounting consistently reported tens of dollars; the $500 hard-halt in HEARTBEAT.md rule 1 never fired.
  - root cause: the original HEARTBEAT.md rule 1 said 'Sum `totalCost` for today' — agent correctly summed per-day ($195 < $500) and saw no breach every tick. The rule was meant to be cumulative; the spec was ambiguous and agent took the literal reading.
  - human replied: two changes to HEARTBEAT.md on the controller — (a) cap extended to $1000 hard / $800 warn, (b) summation changed to 'across all days in the response — cumulative, not per-day'. Also wrote the current $600 cumulative into HEARTBEAT.md so the agent knows the starting point. Did NOT inject a user message; next heartbeat tick will re-read the file.
  - necessity: infra (scaffold / heartbeat-spec fix) + agent-limitation (agent did not flag the discrepancy between its own low cost estimate and the gateway endpoint, nor did it notice $195/day burn on idle days as anomalous). Budget-cap miss is a §10 scaffold-side failure — existing §7 says enforcement is two-place (HEARTBEAT rule + operator cron); we only had the HEARTBEAT rule, and it was broken.

- [2026-04-21T02:05:00Z] [final-publish] Publish-clicked notification injected into agent main session
  - agent asked: n/a — human-initiated after I clicked "Publish now" in Partner Center. Agent was in the `ReadyToPublish` state from 01:33 UTC that day, having Slack-pinged me with the exact publish instructions per HEARTBEAT.md rule 2.
  - human replied: used `openclaw agent --session-id d71b8155... -m "Publish now has been clicked (2026-04-21 ~02:00 UTC). TimeZonr should start propagating to the live Microsoft Store within minutes. Next tick, check Partner Center for the state transition from ReadyToPublish → Publishing → Published, update memory/last-status.txt, and post one final Slack summary with the public apps.microsoft.com URL once it goes live. Then the run is complete — thanks Claw."` Agent ran one turn, verified the public URL at `apps.microsoft.com/detail/9njg0bh2lshs` returned HTTP 200, updated `last-status.txt` to `Published-PublicURLLive`, posted final victory Slack, and stopped.
  - necessity: confirmation of the reserved human action (§6.3 `final-publish`). The publish click is in the free-input allowlist per §6.2, and this injection is the scaffold-level notification of it — not a task-steering intervention. Counts toward the `final-publish` category, not `status-check`.
