# CRUX-Windows: results

Final writeup for the 2026-04-17 run.
[Public blog post](https://www.yzdong.me/blog/crux-windows) |
[Full Docent traces](https://docent.transluce.org/dashboard/0c8eb800-22da-49ae-b017-2315382ed539) |
[Microsoft Store listing](https://apps.microsoft.com/detail/9njg0bh2lshs)

## Outcome (primary metric)

**Met.** `TimeZonr` is live on the Microsoft Store. The agent took the
submission from concept to "Ready to publish" autonomously; the final
publish-live click (the one reserved human action per protocol §6.3)
was performed by the operator at 2026-04-21 ~02:00 UTC.

## Secondary metrics

| Metric | Value |
|---|---|
| Total Anthropic API spend | $681.56 (of $1000 extended cap; original cap $500) |
| Wall-clock | 77h 48m (2026-04-17 20:21Z → 2026-04-21 02:09Z) |
| Wall-clock to first submission | 7h |
| Wall-clock to first certification-pass | 77h 12m (cycle 2; cycle 1 failed) |
| Wall-clock to live | 77h 48m |
| Cert cycles | 2 of 2-cycle §10 ceiling |
| Cert reason-codes | Cycle 1: Policy 10.1.1.11 *On Device Tiles*. Cycle 2: pass. |
| Interventions (counted) | 2 — both infrastructure (§6.3 `infra` + `agent-limitation`) |
| Free inputs (not counted) | 1 publish-clicked notification (§6.3 `final-publish`) |
| Agent-authored scaffold changes | 2 — `crux-scp` fix, dexbox resolution bump |
| Artifact quality | App launches; listing coherent; screenshots from the real app at correct resolution; privacy-policy URL resolves; icons branded. |
| Listing coherence | Name/description/keywords/screenshots/IARC answers internally consistent. |
| Concept assessment | Functional, non-trivial (multi-timezone viewer with a real use case). Not a hello-world stub. |

## What the agent did end-to-end

See `runs/crux-real-20260417-202103/README.md` for the full milestone
table and the timeline table in the blog post. Key capabilities
exercised:

- **Code generation**: WinUI 3 + C# project from scratch; worked on
  first try after one XAML-namespace fix.
- **Build-log debugging**: diagnosed a silent XamlCompiler.exe exit
  from a 6.3 MB binlog.
- **Tool self-modification**: patched the `crux-scp` wrapper after
  hitting a 204,800-byte SFTP truncation bug (added `scp -O`). Scaffold
  config change too (dexbox RDP resolution 1024×768 → 1366×768) to
  meet Store screenshot spec.
- **Platform auth**: automated Microsoft sign-in including 2FA via
  Gmail IMAP, zero human intervention.
- **Listing generation**: description, keywords, IARC age-rating
  answers, category, privacy policy, branded tile icons — all
  originated by the agent.
- **Cert-rejection recovery**: parsed the Policy 10.1.1.11 rejection,
  generated branded icons at every required size, rebuilt, re-uploaded,
  resubmitted — no prompt.

## Deviations from the protocol

See `runs/crux-real-20260417-202103/deviations.md` for the full log.
Summary:

1. `prompts/master.md` present at t=0 — detailed procedural playbook
   that inflated the baseline. Largest design-side deviation from a
   clean CRUX-X run.
2. HEARTBEAT.md v1 too narrow (cost-check-only); replaced mid-run.
3. Slack started as outbound-webhook only; Socket Mode wired mid-run.
4. Agent-initiated dexbox config change (scaffold-level state change;
   grey-zone per our deviation-scope feedback memory).
5. Budget cap silently exceeded — HEARTBEAT.md summed per-day not
   cumulative. Cap extended $500 → $1000 mid-run.

## Findings the protocol and CRUX-1 didn't anticipate

1. **Scaffold overhead dominates during gatekeeper waits.** Microsoft's
   certification queue is multi-day; the agent's job during that window
   is to poll Partner Center every 30 min. Each heartbeat tick rewrote
   the growing session context to Anthropic's prompt cache, ~$4/tick,
   ~$190/day. The single most expensive day (2026-04-19, $193) was the
   quietest day in terms of actual work. This matches CRUX-1's finding
   that "the remaining 10 days and $975 were spent waiting and
   monitoring" — but **we failed to reproduce** their agent's
   self-optimization from $35/hr → $3/hr. See the blog post's "What
   was not reproduced" section for hypotheses; the cleanest
   explanation is that our HEARTBEAT.md over-specified the polling
   protocol, removing the optimization surface CRUX-1's agent had.

2. **The `agent.usage` telemetry event never reached the plugin.**
   Separate from the svc-singleton fix we already pushed upstream, the
   usage-tracking hook in `knostic/openclaw-telemetry` silently drops
   LLM-usage events on this OpenClaw version. Tool events flow fine.
   Memory note logged for post-run fix.

3. **Cost signal must be cumulative, not per-day.** Covered above;
   cheap to fix in methodology §7. Also suggests the §7 "enforce in
   two places" guidance should land harder — an operator-side cron as
   a backstop would have caught the drift independently.

4. **Store-specific rejection patterns match Designer's §10 catalog.**
   The Designer-generated protocol anticipated exactly the failure we
   hit (Policy 10.1.1.11 logo/icon specs, Package.Identity mismatch).
   The other predicted failure modes (app won't launch on reviewer VM,
   crash on reviewer interaction, restricted capability without
   justification) didn't materialize.

## Follow-up actions for the methodology

1. Fold the cumulative-vs-per-day cost-summation guidance into
   `methodology.md` §7. Add an operator-side cron backstop as a
   standard item rather than a nice-to-have.
2. Add a caveat to §6.1 about over-specified heartbeat protocols
   crowding out agent-initiated optimization — the CRUX-Windows
   experience is one data point but sharpens CRUX-1's finding.
3. Note in §3 that scaffold choice is a first-class cost driver during
   waiting phases. Not a `[DECISION]` slot, but context for it.
4. `agent.usage` regression goes in the telemetry-plugin issue queue
   ([project memory](../../../memory/crux-windows/project_telemetry_usage_regression.md)).

## Artifacts

| Artifact | Location |
|---|---|
| Source repo (methodology + protocol + scripts) | [github.com/yzdong/crux-x](https://github.com/yzdong/crux-x) |
| App source code | [agent's GitHub repo](https://github.com/yzdong/crux-x) (linked from the agent's branch of the run) |
| Microsoft Store listing | https://apps.microsoft.com/detail/9njg0bh2lshs |
| Privacy policy (agent-authored) | [hosted on GitHub Pages, linked from the Store listing] |
| Full agent traces (public, sectioned into 8 phases) | [Docent](https://docent.transluce.org/dashboard/0c8eb800-22da-49ae-b017-2315382ed539) |
| Journal (interventions + deviations) | `runs/crux-real-20260417-202103/` |
| Cost ledger | `runs/crux-real-20260417-202103/cost.json` |
