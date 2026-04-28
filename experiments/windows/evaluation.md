# Designer-vs-Actual evaluation

Evaluation of `protocol.md` (the Designer's output, generated from
`/methodology.md` + the target-task description) against the actual
CRUX-Windows implementation as it existed when the first run kicked off
on 2026-04-17. Goal: surface template gaps and protocol-divergences.

Methodology: for each section §1–§10, classify the Designer's decisions
relative to what we actually did:

- **Match** — same substantive choice
- **Designer better** — Designer's call is sharper than ours; our actual
  implementation should be upgraded to match
- **Clean divergence** — Designer made a different but defensible choice;
  no clear winner
- **Template gap** — the template's guidance was underspecified and the
  Designer legitimately surfaced the ambiguity (see Appendix C of
  `protocol.md`)

## §-by-§ findings

### §1. Hypothesis + success criteria — Designer better

Designer's **two-tier primary** ("listing is live" with a recorded
alternate of "Ready-to-publish") is sharper than ours. Our original
implementation had only "live" as the success criterion, which would
have forced us to extend the run beyond 14 days if Microsoft's review
cycle + operator availability didn't line up.

Designer's 7-item secondary list (cert cycles + reason codes, artifact
quality, listing coherence, concept novelty) is more detailed than our
3-item version (intervention count, spend, wall-clock).

### §2. Task specification — Designer better

Designer's out-of-scope list is substantially more explicit:
no Stack Overflow posting, no external paid signups, no crypto, no
social media, no invented API keys, no backend beyond free static
hosting. Our actual run had none of this written down.

### §3. Inputs — Clean divergence + Designer better

Divergent: Designer proposed `<your-gcp-project>` as the GCP project name
vs. our actual `<your-gcp-project>`. Cosmetic.

Designer better: creds via Bitwarden CLI indirection (agent reads item
names; creds never in plaintext on disk) vs our plaintext
`~/.dexbox/shared/creds.json`.

Designer explicitly honored `methodology.md`'s "no playbook file"
guidance — no `prompts/master.md`-equivalent. Our actual run shipped
with the inflation artifact present (see `agent/master.md`).

### §4. Outputs — Designer better

Designer specifies **hourly GCS mirror** of transcripts for crash
safety. Our setup dumped only at run end; a controller crash mid-run
would have lost everything back to the last deploy.

Per-run subdirectory convention (`runs/<run-id>/`) was established by
the Designer; our actual run used a flat directory layout until the
2026-04-18 reorg.

### §5. Telemetry and observability — Match + Designer better

Same knostic plugin, same hash chain, same redaction, same Docent
target. Designer explicitly specifies the Docent sectioning convention
(bootstrap / concept-pick / build / msix-sign / listing-prep /
first-submit / review-cycle-N / release-handoff). Our actual run didn't
plan the sectioning up front.

### §6. Agent instructions — Designer better (several places)

Bootstrap message matches exactly.

Designer's evaluation framing adds "**don't fabricate a value to avoid
asking**" and "**silence is the worst outcome**" — both load-bearing
phrases we didn't include. CRUX-1 paper §3.3 specifically identified
fabrication as a failure mode our framing didn't guard against.

**Slack Socket Mode from t=0**. We launched with outbound webhook only
and cutover to Socket Mode mid-run as an intervention after the agent
stalled. Designer got this right from the start.

**HEARTBEAT.md rule 3 ("continue main task") from t=0.** Our initial
HEARTBEAT.md was cost-check-only and caused a 45-min stall when the
agent finished a phase and heartbeat ticks returned `HEARTBEAT_OK`
without driving work forward. Designer's version had all three rules
from day one.

### §7. Constraints — Designer better

Designer adds an **operator-side cron backup** ($450/$500 Slack alerts
independent of the agent's self-halt). Belt-and-suspenders that we
didn't have.

Designer explicitly forbids the agent from touching the
`yzdong/crux-x` repo itself (PAT-scoped enforcement). Our
actual agent COULD have written to the experiment repo because the
PAT wasn't scoped this carefully.

### §8. Pre-run validation — Designer better

**9-check preflight** (ours is 7). Additions: disk + RAM free (1),
`usage-cost` JSON validity (4), dummy-tool round-trip for telemetry
plumbing (9). Check 9 specifically would have caught the 2026-04-17
silent-telemetry-loss bug at preflight instead of mid-run.

Designer specified a **concrete dry-run protocol** with a canonical
bootstrap message. Our actual run did ad-hoc smoke tests with no
canonical script.

Designer's workspace reset is a **9-step procedure** including
archiving the pre-reset state to GCS. Ours was informal.

### §9. Replication discipline — Match

Same invariants, same acceptable-variation list, same deviation-
logging pattern. Designer puts the deviation log per-run
(`runs/<run-id>/deviations.md`) vs. our single long-lived memory file;
the per-run placement is cleaner.

### §10. Failure mode catalogue — Designer much better

Designer's Microsoft-Store-specific failure list had no equivalent in
our actual setup — we discovered failures as they happened. Includes:
age rating declined, package identity mismatch, logo/screenshot spec
failures, restricted-capability rejections, non-functional privacy
URL, "doesn't launch on reviewer VM", crash on reviewer interaction,
policy 10.1 "too simple," trademark conflicts, 2-cycle review budget
ceiling, Partner Center UI drift.

Plus scaffold-side failures we did hit (silent telemetry loss, gateway
death on SSH disconnect, target VM console locks, UAC input loss) and
agent-side ones (hallucinated submission state, over-asking at
concept-pick, over-scope concept, privacy-policy shortcut via gist,
NO-REPLY stall, memory regression).

## Template gaps surfaced by the Designer (Appendix C of protocol.md)

The Designer appropriately flagged 10 places where `methodology.md` did
not give enough guidance to decide confidently. The most important:

- **C1**: primary-metric strictness when the final step is human-
  reserved. `methodology.md` §1 does not address this class of task;
  the Designer invented the two-tier metric. The template should
  probably make this pattern a first-class option.
- **C3**: what counts as "acceptable free infrastructure". The template
  says no paid services but doesn't draw the line between paid and
  free-tier (Cloudflare Workers? Deno Deploy? Vercel?).
- **C6**: is operator-assisted sign-in a "free" input or a baseline
  inflation? The Designer categorized it as free; the template's §6.2
  guidance is silent on the "sign-in once then hand off" pattern.
- **C8**: N≥2 dry runs or just 1? CRUX-1 reportedly ran more. Template
  §8 suggests one bounded smoke per fresh install.
- **C9**: how should the operator respond if the agent over-asks at
  concept-pick? Designer's answer is to reply once with "you pick" and
  log as `status-check` (counted). Template §6.3 doesn't prescribe.

## Overall

Template is doing its job. Designer produced a protocol **materially
better than our actual implementation** along 9 of 10 section axes. The
deltas where the Designer came up short are template-side gaps, not
Designer errors — and the Designer correctly surfaced them as
Appendix-C open questions for the experiment commissioner.

Actionable follow-ups:

1. Tighten `methodology.md` §1 to address human-reserved final steps
   (C1).
2. Tighten §6.2's free-vs-counted guidance to include the sign-in
   handoff pattern (C6).
3. Add a concrete dry-run protocol to §8 that looks like the
   Designer's. Current §8 is abstract.
4. Add a Microsoft-Store-flavored failure mode catalogue to future
   protocols as a seed for §10 (not in the template itself — task-
   specific).
