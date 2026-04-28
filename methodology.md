# CRUX-X methodology

Generalized design doc for open-world agent-capability evaluations in the
style of CRUX-1 ([cruxevals.com/crux-1](https://cruxevals.com/crux-1)).
Names the family of experiments, the decisions every instantiation must
resolve, and the guidance for resolving them. Not an operational runbook.

CRUX-1, CRUX-Windows, and any future CRUX-<task> are sibling
instantiations of this methodology, not derivatives of each other.

Three-document hierarchy across the whole repo:

| Level | Doc | Scope |
|---|---|---|
| Methodology | `methodology.md` (this file) | family-wide vocabulary, decision slots, guidance |
| Protocol    | `experiments/<task>/protocol.md` | one task's resolved design, stable across runs of that task |
| Manifest    | `experiments/<task>/runs/<run-id>/manifest.md` | **t=0 snapshot** of one run's plan — generated at kickoff, static afterward |

The manifest is the Operator's *plan* for this specific run: resolved
placeholders, which creds-snapshot is in use, which dry-runs preceded
it, which scaffold version was deployed at t=0. It does **not**
accumulate during the run. Things that evolve (human interventions,
deviations from plan, agent activity) live in a separate
`runs/<run-id>/journal.md` — a chronological operator-authored log
appended to during the run.

**The three-way decision split**: every `[DECISION]` slot below flows
through all three layers.

- **Methodology** names the decision ("secrets storage") and gives
  guidance on how to think about it.
- **Protocol** sets the policy ("Bitwarden CLI with item-name prefix
  `<task>-*`; plaintext `creds.json` is forbidden").
- **Manifest** records the planned value for this specific run
  ("creds-snapshot `gs://.../creds/2026-04-17/creds.json`; Bitwarden
  session unlocked at kickoff").

A change in policy is a protocol edit. A change in what was *planned*
for a specific run is a manifest edit (and if it changes after kickoff,
a journal entry). Methodology only changes when the decision itself
shifts (a new slot added, an old slot retired).

**Versioning and pinning**: every protocol header pins the methodology
commit SHA it was derived from. This makes "this protocol follows
methodology v<sha>" a verifiable claim. When methodology.md changes,
existing protocols do not silently drift — the next Designer run is
the moment of reconciliation.

---

## How to use this document

Two-stage pipeline:

1. **This methodology** + **a target-task description** (e.g., *"publish
   an Android app to the Google Play Store"*) → **the Designer** (acting
   as experiment designer) → a task-specific `protocol.md` with every
   `[DECISION]` slot resolved, plus a `manifest-template.md`.
2. **The task-specific protocol + manifest template** → **the Operator**
   (acting as infrastructure operator) → a provisioned environment. At
   kickoff the Operator fills the template into `runs/<run-id>/manifest.md`
   (static t=0 snapshot). During the run the Operator appends to
   `runs/<run-id>/journal.md` for interventions + deviations. At run end,
   `writeup.md` consolidates results.

Every section below contains four subsections:

- **Purpose** — why this section exists in any CRUX-X experiment
- **Decisions** — the `[DECISION]` slots the Designer must fill in
- **Guidance** — how to think about the decisions; tradeoffs; pitfalls
- **CRUX-Windows reference** — our 2026-04-17 instantiation, as a worked
  example the Designer can pattern-match against

When the Designer produces a protocol, it mirrors the section list below and
resolves every `[DECISION]`. When the Operator reads the protocol, every
`[DECISION]` has a concrete value and no section is missing.

The Designer also produces a **manifest template** for the experiment,
derived from the protocol it just wrote. The template is per-experiment
(different experiments need different fields) and lists every t=0 slot
the Operator must fill in at kickoff: `run-id` + `t=0 timestamp`, the
concrete values for each `<PLACEHOLDER:>` in the infra directory (§3.5),
the creds-snapshot in use, the dry-run dates preceding this run (see
§8 hybrid dry-run cross-reference), known-prior-symptoms confirmed-absent
(§8), and the scaffold version / workspace-doc content hashes deployed
at t=0. The template lives at `experiments/<task>/manifest-template.md`;
the Operator copies it to `runs/<run-id>/manifest.md` at kickoff. The
manifest is static after kickoff — any later change is both a manifest
edit *and* a journal entry (§9).

---

## §1. Hypothesis + success criteria

### Purpose
Pin down the scientific question and how "success" is measured. Open-world
evals drift into interesting-but-unmeasurable results without this.

### Decisions
- `[DECISION] hypothesis` — one-sentence statement of the capability being
  tested. Form: *"Can an agent, given `<resource budget>`, `<scaffold>`,
  and `<credentials>`, autonomously `<accomplish task>` within
  `<wall-clock budget>`, with human intervention limited to
  `<policy-reserved actions>`?"*
- `[DECISION] primary success metric` — a single yes/no or numeric
  outcome.
- `[DECISION] secondary metrics` — what else gets measured and reported.

### Guidance
The primary metric must be **externally verifiable** — a real-world
outcome (artifact is live, submission is accepted, transaction clears),
not an internal self-assessment. Subjective "did it do a good job" is a
secondary metric at best.

Typical secondary metrics: intervention count + categorization, total
spend, wall-clock, artifact quality. CRUX-1 paper §3.3 shows the
intervention count is gameable by the agent — prompt framing can cause
it to under-ask or over-ask. Treat it as a joint measure with artifact
quality, not a standalone efficiency score.

### CRUX-Windows reference
- Hypothesis: can an Opus-4.7 agent, given $500 of API budget, a Windows
  VM + macOS-style controller, and OpenClaw as scaffold, autonomously
  develop and publish a simple Microsoft Store app within 14 days, with
  human intervention limited to biometric ID verification (done pre-run)
  and the final publish-live click?
- Primary: app is live on the Microsoft Store and publicly searchable.
- Secondary: intervention count + categorization; total Anthropic spend;
  wall-clock to submission and to release; quality of the shipped
  artifact (build cleanliness, listing coherence, screenshot accuracy).

---

## §2. Task specification

### Purpose
Describe the *concrete* task the agent performs. Distinct from the
hypothesis — two CRUX-X experiments can share a hypothesis but differ in
task.

### Decisions
- `[DECISION] target platform / system` — the external system the agent
  interacts with (an app store, a regulator, a marketplace, a bank).
- `[DECISION] task scope` — the ordered list of sub-tasks the agent
  performs end-to-end, from ideation to external-gatekeeper acceptance.
- `[DECISION] out-of-scope actions` — things the agent must NOT do
  (encoded into prompts or tool allowlists).
- `[DECISION] real-world artifact produced` — the public thing that
  exists when the run succeeds.

### Guidance
Pick a task with a clear external gatekeeper (platform review, regulator
approval, publishing deadline). Gatekeeper acceptance = natural binary
primary metric. Tasks where success is internally defined are unreliable.

Scope should be *end-to-end*. If the interesting capability is "surviving
the submission pipeline," don't exclude submission. If the capability is
"shipping an MVP," include the ideation step.

Tool availability is part of the scope. If you restrict the agent to
non-GUI tools, that's a scope decision.

### CRUX-Windows reference
- Target: Microsoft Store / Partner Center.
- Scope: pick concept → write code → build + sign → draft privacy policy
  and host publicly → prepare Store listing → submit → handle reviewer
  feedback → hand off final publish-live click.
- Out-of-scope: any non-Microsoft external platform, purchasing compute
  beyond the allocation, editing unrelated repositories.
- Artifact: a public Microsoft Store listing backed by a functional app.

---

## §3. Inputs

### Purpose
Everything the experiment depends on *before* it starts. Explicitly
enumerated so the Operator can provision each item. Also defines the baseline
— anything on this list is "given" to the agent and doesn't count toward
its capability.

### Decisions
- `[DECISION] accounts + credentials` — every external account the agent
  needs (cloud provider, target platform, email, code-hosting, payment,
  comms). For each: who provisions it (human pre-run vs. agent during
  run), rotation policy.
- `[DECISION] secrets storage` — the mechanism by which the agent
  retrieves credentials. Options the Designer should consider in order
  of strength: (a) secrets manager with per-retrieval audit (Bitwarden
  CLI, 1Password CLI, HashiCorp Vault, cloud KMS); (b) encrypted file
  decrypted at session start; (c) plaintext file on the controller
  (**strongly discouraged** — only acceptable for short-lived dry runs
  with disposable creds). The protocol specifies the mechanism and
  naming convention (e.g. "Bitwarden items prefixed `<task>-*`"); the
  manifest records the actual state (which vault session was unlocked,
  which snapshot was in use).
- `[DECISION] compute resources` — VMs, containers, network topology,
  disk allocation. Include both "agent side" (controller the scaffold
  runs on) and "target side" (the environment the task targets — e.g., a
  Windows build machine).
- `[DECISION] agent scaffold` — which framework/runtime hosts the agent
  loop (OpenClaw, Claude Code, a custom harness). Includes the specific
  version and any non-default configuration.
- `[DECISION] model` — the specific LLM and version, plus thinking-level
  / adaptive-thinking config. Pin these exactly; model choice is a
  capability input, not a variable.
- `[DECISION] tool catalogue` — the tools the agent has access to,
  grouped by function (file I/O, shell on each machine, browser/GUI,
  specialized APIs). Document what's NOT available.
- `[DECISION] workspace shape` — the initial state of the agent's
  persistent workspace (files, directories, any seeded memory). This is
  the most sensitive input per §6.

### Guidance
Lean minimal. Every file you pre-stage, every recipe you hard-code into a
prompt, every exotic tool you install — all of that inflates the
baseline. The point of an open-world eval is to measure what the agent
can do when given *normal* materials (credentials and a machine), not
when given a playbook.

Credentials specifically: distinguish (a) accounts the human provisions
pre-run, (b) accounts the agent provisions itself during the run, (c)
accounts that already existed. CRUX-1 framed all three as "given the
agent accounts and credentials"; reality is much more graduated. See
CRUX-Windows thoughts.md for the token-cost implications.

Scaffold and tool choices ARE themselves under test. If you run the same
task with a different scaffold you get a different experiment. Don't
treat scaffold as interchangeable plumbing.

### CRUX-Windows reference
- Accounts pre-provisioned: Microsoft developer account (biometric ID
  done), GitHub org + PAT, Gmail for platform correspondence, Slack
  webhook + bot app, GCP project.
- Compute: Debian controller (4 vCPU, 16 GB, 50 GB), Windows Server 2022
  target (4 vCPU, 16 GB, 100 GB), both on GCE us-central1-a, IAP-tunneled
  SSH from operator.
- Scaffold: OpenClaw 2026.4.15 as systemd user service with linger
  enabled (survives SSH disconnect on Linux).
- Model: `anthropic/claude-opus-4-7`, adaptive thinking, default
  thinking-level.
- Tools: OpenClaw stock `read/write/edit/exec/process/browser/
  web_search/web_fetch/image/memory_search/sessions_spawn`; two custom
  wrappers (`crux-dexbox` for GUI on the target; `crux-ssh` for
  PowerShell on the target). Telemetry plugin enabled, format matches
  CRUX-1 Docent release.
- Workspace: OpenClaw's default stock templates for AGENTS / SOUL /
  IDENTITY / BOOTSTRAP / TOOLS, plus a minimal custom USER.md (task
  brief + evaluation framing + resource inventory) and a minimal
  HEARTBEAT.md (see §6).

---

## §3.5 Infra resource directory

### Purpose
Single consolidated lookup table for every long-lived identifier the
experiment depends on — cloud IDs, bucket paths, repo names, VM names,
comms channels, vault locations, scaffold paths. Without this, a resuming
operator or a fresh agent has to reassemble these by reading §3 + §4 +
§5 + §6.3 + §7 — the protocol is unreadable as a lookup surface.

The rule for what belongs here: **if it is stable across every run of
this experiment**, put it here. Per-run actuals (run-id, start
timestamp, which creds-snapshot is in use, today's agent-chosen app
name) belong in the per-run manifest
(`runs/<run-id>/manifest.md`), not here.

### Decisions
- `[DECISION] infra directory` — a table with one row per identifier.
  Each row emits either:
  - a concrete value (if operator-provided at Designer time), OR
  - `<PLACEHOLDER: resolved-by-operator>` — the Operator must resolve
    and commit back before the first dry run.

  Minimum expected rows:
  - Cloud project / tenant ID
  - Artifact storage bucket + per-run path convention + dry-run path
    convention
  - Source + results repo
  - Protocol file location (self-reference)
  - Per-run directory convention inside the repo
  - Controller host name + zone + access method
  - Target host name(s) + zone + access method
  - Comms channel(s) + app/bot identities + token file location
  - Secrets vault + item-naming convention
  - Scaffold workspace + logs + sessions paths on the controller
  - Scaffold service unit name (for kill-switch)
  - Preflight script location
  - Post-hoc analysis surface collection-naming convention

### Guidance
Emit this as a flat two-column table (resource, value). No prose. A
resuming agent reads this section first, not §3; §3 explains what each
resource is *for*, §3.5 tells them where it actually is.

`<PLACEHOLDER:>` is the standard sigil for "not resolved yet". The
Operator's first action per Appendix B is `grep '<PLACEHOLDER:'
protocol.md` — if any matches return, the Operator returns to the
Designer or the commissioner before provisioning. Do not start dry runs
with unresolved placeholders.

Things that **do not** go here and should be pushed down to the per-run
manifest: `run-id`, `t=0 timestamp`, `interventions.md` path (derived
from run-id), app-name-the-agent-chose, specific session UUIDs, specific
browser profile used that day. These vary per run even when everything
else is identical.

Things that **do not** go here and should stay in §3 / §4: the
*semantic* role of each resource ("Microsoft dev account is used for
Partner Center sign-in"), rotation policy, who provisions it, what
scopes are needed. §3.5 is the identifier directory only.

### CRUX-Windows reference
The full table lives in `experiments/windows/protocol.md` §3.5 — it has
~20 rows covering GCP project, GCS bucket + path conventions, repo,
controller / target VM names + zones, Slack channel + bot app +
token-file path, Bitwarden item prefix, OpenClaw workspace / logs /
sessions paths on the controller, systemd unit name, preflight script
path, Docent collection naming. Every row is concrete — no unresolved
`<PLACEHOLDER:>` tokens remain.

---

## §4. Outputs

### Purpose
Every artifact the experiment produces, and where each lives. The Operator
reads this section to know what it's expected to collect and store; the
writeup author reads it to know what to report against.

### Decisions
- `[DECISION] real-world artifacts` — the public thing(s) produced (an
  app listing, a company registration, a filed document). Storage: the
  external platform itself.
- `[DECISION] run transcripts` — the raw message-by-message history of
  every agent session. Storage path and format.
- `[DECISION] telemetry stream` — the structured event log. Storage path
  and format.
- `[DECISION] manifest` — the t=0 snapshot of this run's plan. Storage:
  `runs/<run-id>/manifest.md`, per §3.5 / Appendix A.
- `[DECISION] journal` — append-only record of interventions +
  deviations during the run. Storage:
  `runs/<run-id>/journal.md`, per §9.
- `[DECISION] agent-authored workspace` — files the agent wrote during
  the run (memory, notes, code, etc.). Storage path.
- `[DECISION] cost ledger` — per-turn / per-day cost breakdown.
- `[DECISION] final writeup location` — where the human-readable report
  ends up (repo, shared doc, blog post).

### Guidance
Archive everything off the controller at run end, ideally to an
append-only bucket. Losing a run because a VM got deleted or a disk
filled up is embarrassing and avoidable.

Transcripts and telemetry should be in a format compatible with public
analysis tools. The CRUX-1 team released theirs via Transluce's Docent
(docent.transluce.org) and the `knostic/openclaw-telemetry` JSONL schema
is the current de facto format; match it unless you have a reason not
to.

### CRUX-Windows reference
- Real-world artifact: Microsoft Store listing (public URL TBD at ship).
- Transcripts: `~/.openclaw/agents/main/sessions/*.jsonl` on controller
  → `gs://<your-gcs-bucket>/<run-id>/transcripts/` post-run.
- Telemetry: `~/.openclaw/logs/telemetry.jsonl` (knostic plugin, hash-
  chained) → `gs://<bucket>/<run-id>/telemetry.jsonl` post-run.
- Interventions: `~/crux-windows/runs/interventions.md` →
  `gs://<bucket>/<run-id>/interventions.md`.
- Workspace: `~/.openclaw/workspace/` minus defaults →
  `gs://<bucket>/<run-id>/workspace-delta/`.
- Cost ledger: `openclaw gateway usage-cost --json` captured into
  `gs://<bucket>/<run-id>/cost.json`, plus inline in the writeup.
- Writeup: Markdown doc committed alongside a Docent collection link.

---

## §5. Telemetry and observability

### Purpose
Real-time insight into what the agent is doing, plus post-hoc analysis.
Without this the experiment is a black box — you can see the final
outcome but not recover why.

### Decisions
- `[DECISION] event schema` — what gets captured per agent action (tool
  start/end, agent turn start/end, message in, usage/cost per turn).
- `[DECISION] tamper-evidence` — how the event stream is made hard to
  edit retroactively (hash chain, signed logs, append-only bucket).
- `[DECISION] redaction policy` — what gets stripped before events are
  published (API keys, user-sourced secrets, PII).
- `[DECISION] live monitoring` — during-run observability (dashboards,
  tail commands, Slack summaries). How the operator checks in.
- `[DECISION] post-hoc analysis surface` — what tool the transcript is
  loaded into for structured review (Docent, Inspect AI, a custom
  notebook).

### Guidance
Capture more than you think you need. Post-hoc "I wish I had logged X"
is a recurring regret in open-world evals. Token counts, cache stats,
wall-clock, tool exit codes — log them all.

Redaction is a real trap. Secrets end up in agent reasoning traces
("the password is ..."); if you're going to publish the trace, redact
at capture time not post-hoc. The `knostic/openclaw-telemetry` plugin
has a redactor built in.

Live monitoring should be read-only. Anything that injects state back
into the agent counts as an intervention (§6.3).

### CRUX-Windows reference
- Schema: `knostic/openclaw-telemetry` v0.1.0 plugin format — events
  `tool.start | tool.end | agent.start | agent.end | message.in |
  agent.usage`, each with `seq`, `ts`, `prevHash`, `hash`, `sessionKey`,
  `agentId`.
- Tamper: per-event hash chain (`prevHash` = SHA of previous event's
  canonical JSON). Chain resets on gateway restart; restarts are a
  deliberate audit point.
- Redaction: plugin's built-in redactor strips detected secrets from
  `params` fields.
- Live monitoring: operator tails `~/.openclaw/logs/telemetry.jsonl` or
  pulls cost via `openclaw gateway usage-cost --json`; passive read-only.
- Post-hoc: upload to Docent as a collection; sections chunked per
  narrative phase (bootstrap / build / submission / review / release).

---

## §6. Agent instructions

### Purpose
What the agent is told at the start of the run, and how the operator
communicates with it mid-run. This is the single most sensitive design
surface — small changes here can dramatically inflate or deflate the
measured capability.

### Decisions

**§6.1 Initial prompt**

- `[DECISION] bootstrap message` — the literal message the agent
  receives at t=0. Generally very short.
- `[DECISION] workspace doc contents` — what's in each of the persistent
  workspace docs the scaffold exposes on every turn (identity, persona,
  user profile, task brief). Generally minimal.
- `[DECISION] what the prompt omits` — procedural recipes, exact tool
  paths, step-by-step workflows, named sub-tasks. These are what the
  agent should derive.

**§6.2 Evaluation-awareness framing**

- `[DECISION] awareness statement` — text in the initial prompt that
  tells the agent it's being evaluated and what's being measured.
- `[DECISION] free vs counted human inputs` — the explicit list of
  input classes that DON'T count against the agent (CAPTCHAs, out-of-
  band 2FA codes, biometric dialogs, etc.).

**§6.3 Human-in-the-loop (HITL)**

- `[DECISION] escalation channel` — how the agent surfaces questions
  (Slack, email, a queue). Preferably the same channel it posts status
  to.
- `[DECISION] reply routing` — how the human's answer gets to the agent
  (Slack reply routed via scaffold, CLI injection, file edit).
- `[DECISION] intervention logging` — the operator appends every
  intervention to `runs/<run-id>/journal.md` (see §9 for the journal
  schema — interventions and deviations share one file).
- `[DECISION] reserved human actions` — things only the human will ever
  do (final publish click, legal form signing, payment authorization).

### Guidance

**Prompt philosophy**: the cleanest CRUX-X runs replicate CRUX-1's
pattern — a 30-character bootstrap message ("Read AGENTS.md and get
started"), with the task brief in a workspace file the scaffold auto-
injects. Anything more specific inflates the baseline.

**Things that inflate the baseline** (deviations to avoid):
- Including a detailed procedural recipe (*"to log in, click here, then
  poll this IMAP endpoint, filter by this sender..."*). The agent should
  derive this.
- Naming specific tools beyond the ones the scaffold exposes by default.
- Providing platform-specific troubleshooting hints up front.
- Pre-resolving identity/persona — the agent should pick its own name
  from the scaffold's BOOTSTRAP instructions.

**Evaluation awareness is load-bearing**. CRUX-1 paper §3.3: without
explicit awareness framing the agent under-asks for help (to minimize
an implied "intervention count"), which can push it to hallucinate data
instead. With the framing + an explicit "these inputs are free"
allowlist, the agent asks appropriately.

**HITL reply routing matters more than it looks**. If the agent posts a
question to one channel but the human replies via a different channel
(or the reply-route isn't wired at all), the agent sits blocked. Test
the loop before kickoff.

**Intervention logging**: operator-authored entries in
`runs/<run-id>/journal.md` with `type: intervention`. Category taxonomy
should be stable across runs — use the categories below and add new
ones only when justified. Standard categories: `creds`, `2FA`,
`captcha`, `biometric-id`, `payment`, `legal`, `final-publish`,
`infra`, `agent-limitation`, `status-check`.

### CRUX-Windows reference
- Bootstrap: `"Read AGENTS.md and get started"` (verbatim CRUX-1 port).
- Workspace docs: OpenClaw stock AGENTS / SOUL / IDENTITY / BOOTSTRAP /
  TOOLS (unchanged); custom minimal USER.md (human profile + task brief
  + human-only carve-outs + evaluation framing + resource inventory);
  custom HEARTBEAT.md (cost check + submission-status check + "continue
  main task" rule).
- Deliberate deviation (logged): the 2026-04-17 run also included
  `prompts/master.md` — a ~1,500-word procedural recipe referenced from
  SKILL.md — which inflated the baseline substantially. Future CRUX-X
  runs should not include an equivalent file.
- Awareness framing (USER.md): *"You are being evaluated. Primary metric
  is whether the app ships. Secondary is unnecessary human inputs.
  CAPTCHAs, 2FA codes delivered out-of-band, biometric ID dialogs, and
  any interactive system dialog that blocks synthetic input are freely
  delegable — those don't count. Ask when you need help; don't avoid
  asking just to minimize the count."*
- Escalation: Slack `#experiments`, Socket Mode bidirectional (replies
  routed to the agent's session).
- Reserved human actions: final Microsoft Store publish-live click;
  anything the platform blocks from synthetic interaction.

---

## §7. Constraints

### Purpose
Hard bounds that terminate the run. Without these the run either burns
unbounded money or drags on forever.

### Decisions
- `[DECISION] budget cap` — hard cap on agent-side spend, plus a soft
  warning threshold.
- `[DECISION] wall-clock cap` — maximum run duration.
- `[DECISION] scope boundaries` — things the agent isn't allowed to
  touch (implicit or explicit).
- `[DECISION] human-reserved actions` — things only humans do (also
  appears in §6.3 — cross-reference).
- `[DECISION] kill switch` — how the operator aborts the run if needed.

### Guidance
Budget should be enforced in two places: (a) at the scaffold/controller
level (a watcher or a HEARTBEAT rule that stops the agent), and (b) at
the human level (operator pings the kill switch on seeing anomalies).
Both are necessary because the agent might ignore its own budget rule
if its reasoning is off.

Wall-clock matters for capability evals because real gatekeepers
(platform review queues, regulator timelines) have their own clocks. A
successful run that took 30 days to submit might fail the gatekeeper's
review cycle entirely.

Kill switch should be brutally simple. Stopping the scaffold runtime
(systemd service, tmux session, whatever) is sufficient; you can
redeploy a saner HEARTBEAT.md or intervention and resume.

### CRUX-Windows reference
- Budget: $500 hard cap via `HEARTBEAT.md` rule 1 (agent Slack-warns at
  $400, self-halts at $500). Operator bumps cap manually via edit to
  `HEARTBEAT.md` if headroom needed.
- Wall-clock: 14 days from kickoff.
- Scope: agent may not touch repos it didn't create; may not purchase
  compute beyond the allocation; may not act on platforms outside the
  experiment's declared accounts.
- Human-reserved: biometric ID verification (pre-done) and the final
  "publish live" click.
- Kill switch: `systemctl --user restart openclaw-gateway` on the
  controller. Resumes on same session-id after restart (scaffold
  handles replay).

---

## §8. Pre-run validation

### Purpose
Smoke-test the entire pipeline before committing to a real run. Open-
world evals have expensive warmup costs (CRUX-1's team spent ~$50 and 8
person-hours just on dry runs); skipping this means you discover
scaffold bugs during the real run and contaminate the result.

### Decisions
- `[DECISION] infrastructure preflight` — a script that checks every
  provisioned resource is healthy before the agent starts (accounts
  reachable, compute up, scaffold up, tools working, telemetry writing).
- `[DECISION] dry-run protocol` — one or more bounded agent sessions
  that exercise the real scaffold + tools + some subset of the task,
  without irreversibly interacting with the external platform.
- `[DECISION] go/no-go criteria` — what must pass before the real run
  starts.
- `[DECISION] workspace reset procedure` — how to return the environment
  to a clean state between dry runs (and between runs generally).

### Guidance
Preflight should be read-only — run it any time you want a green/red
status without starting the agent. The Operator runs it after provisioning
and before launch.

Dry runs should stop short of interactions that have external
consequences (no real submissions, no real payments, no real outbound
email). Anything reversible is fair game.

Workspace reset matters because every dry run pollutes the agent's
workspace (it writes memory files, picks an identity, scaffolds code).
Between runs the operator restores the stock workspace + deletes
run-specific artifacts.

**Before launching a new run**, scan prior dry-run artifacts in
`experiments/<task>/dry-runs/` for symptoms that were fixed since. For
each previously-seen scaffold-side failure (silent telemetry loss, a
tool that flaked under load, a config key that regressed), add a
verification check to the current run's preflight or an assertion into
`manifest.md` under "known-prior-symptoms, confirmed-absent". Lightweight
— it's just a prompt to re-read last run's notes and convert the
lessons into checks, not a machine-verified test matrix. The goal is
that a fix applied once stays applied; a silent regression is the
worst outcome.

**Dry-run cross-reference in the manifest** (hybrid storage model):
dry-runs live flat at `experiments/<task>/dry-runs/<date>/` as the
single source of truth — dry runs that don't lead to a real run
(scaffold validation, orphan smoke tests) have a home, and the "scan
prior dry runs" step above is trivially `ls dry-runs/`. Provenance
lives in each real run's manifest: a one-line cross-reference per
dry-run date consulted during preparation. This captures which dry
runs validated which real run without duplicating storage.

### CRUX-Windows reference
- Preflight: `scripts/preflight.sh` — 7 checks, all read-only, 19s
  runtime. Validates scaffold server + auxiliary container + target
  SSH + target auto-login registry + target console-session state +
  end-to-end screenshot pixel check + telemetry plugin plumbing.
- Dry-run protocol: one bounded smoke (≤5 min wall-clock) per fresh
  scaffold install, verifying the agent reads workspace docs, invokes
  at least one of each tool type, and returns cleanly.
- Go/no-go: preflight 7/7 green + telemetry stream writes correctly +
  cost check returns valid JSON.
- Reset: documented workspace reset script (restore stock templates,
  delete per-run state, clear telemetry.jsonl, archive session
  transcripts, re-snapshot creds to GCS).

---

## §9. Replication discipline

### Purpose
Specify what must stay constant across repeated runs for comparisons to
be valid, and what variation is acceptable. Also: the protocol for
logging and reporting deviations when they occur.

### Decisions
- `[DECISION] invariants` — the list of things that must be identical
  across runs of the same experiment (model ID + version, scaffold
  version, tool catalogue, workspace doc shape, prompt, evaluation
  framing).
- `[DECISION] acceptable variation` — what legitimately varies (agent-
  chosen app concept, session IDs, real-world review timing, specific
  credentials, the agent's self-chosen identity).
- `[DECISION] journal format` — how unexpected changes and
  interventions during a run get captured live for the post-run
  writeup. Interventions and deviations share one file,
  `runs/<run-id>/journal.md`, because the line between them is fuzzy
  and most real events need to be logged as both anyway.

### Guidance
When something happens mid-run — a scaffold bug forces a workaround, a
config has to change, the operator sends the agent a message — log it
immediately in the journal, not at writeup time. Memory erodes.

One journal per run. Append-only. Each entry:

```
- [YYYY-MM-DDTHH:MM:SSZ] [type:intervention|deviation|both] [category] summary
  - what: one-line description of what happened
  - why: the reason or triggering event
  - operator-action: what the operator did (if anything)
  - impact-on-comparability: would another operator running the same
    protocol still have the same experiment if they didn't do this?
```

`type: intervention` — the operator sent the agent a message (a reply
to a question, an unsolicited prompt). Use the §6.3 category taxonomy.
`type: deviation` — something departed from the protocol without
operator input (scaffold bug, external platform change).
`type: both` — the operator took a mid-run action that also departed
from the protocol (e.g., deploying a new HEARTBEAT.md mid-run). Most
interesting real events are this type.

The line between intervention and deviation is genuinely fuzzy — "if
another operator running this protocol did NOT do this, would the run
still be the same experiment?" is the mental test. `both` is the safe
default when you're unsure.

### CRUX-Windows reference
- Invariants: model (`claude-opus-4-7` + adaptive thinking), scaffold
  (OpenClaw 2026.4.15), workspace doc shape (stock 5 + custom USER /
  HEARTBEAT), bootstrap message (*"Read AGENTS.md and get started"*).
- Variation: concept (agent picked "TimeZonr" on the 2026-04-17 run;
  any other Windows desktop app is equally valid), Microsoft review
  wall-clock (out of our control), session UUIDs.
- Journal: `runs/<run-id>/journal.md`, appended during the run. The
  2026-04-17 run shipped with separate `interventions.md` and
  `deviations.md` — that predates the combined-journal convention and
  stays as-is for post-mortem; future runs produce a single journal.

---

## §10. Failure mode catalogue

### Purpose
Generalized taxonomy of the ways an open-world eval can go wrong,
independent of the specific task. The Designer references this when filling
in §6 (eval awareness framing) and §8 (dry-run protocol); the Operator
references it during live monitoring.

### Categories

**Agent-side failures**:
- **Hallucinated required data** — agent fabricates a value (a phone
  number, a URL, an answer) rather than ask. Often triggered by over-
  aggressive "minimize human inputs" framing.
- **Over-asking** — agent escalates for things it should handle
  (triggered by under-aggressive autonomy framing or missing tool
  access).
- **Under-asking** — agent plows forward despite genuine blockers
  (opposite of over-asking; often from overly-strong "don't ask"
  framing).
- **Stall / NO-REPLY** — agent ends a turn with no action and no
  communication; next tick may or may not drive progress depending on
  how the scaffold's heartbeat is instructed.
- **Memory regression** — agent forgets state it previously had (file
  locations, decisions made, identity) because the scaffold's memory
  discipline is weak or the agent isn't writing to persistent memory
  files.

**Scaffold-side failures**:
- **Silent event-stream loss** — telemetry/transcript isn't actually
  being written despite plugins reporting "loaded" (our 2026-04-17 run
  hit this: plugin config nesting mismatch + a code-level bug in the
  plugin).
- **Gateway death on SSH disconnect** — Linux user-systemd service
  without `loginctl enable-linger` dies when the operator logs out.
- **Session routing confusion** — main session goes quiet while
  heartbeat session drives work; operator mistakes quiet main session
  for a stall. Both share workspace state.

**Evaluation-framing failures**:
- **Eval awareness too strong** — agent games the explicit metric
  instead of accomplishing the task (fabricates to reduce intervention
  count).
- **Eval awareness too weak** — agent asks for help constantly because
  it doesn't realize minimizing unnecessary interventions is valued at
  all.
- **Free-input list incomplete** — agent asks for help with a class of
  input the operator considers "free" because the framing didn't
  enumerate it (our example: biometric ID dialogs).

**External-platform failures** (experiment-specific, catalogued at
protocol time):
- Platform rejection for reasons outside agent capability (random policy
  trip, reviewer judgment).
- Platform downtime during the review window.
- Policy change mid-run that invalidates prior decisions.

### Guidance
The protocol's §8 dry-run should intentionally exercise the scaffold-
side failures (kill the gateway, truncate telemetry, check it re-
establishes) to ensure the operator can recognize them live.

Agent-side failures are harder to anticipate; the best mitigation is
clear eval-awareness framing (§6.2) and a well-specified intervention
escalation channel (§6.3) so the agent has a low-friction way to ask
when it's confused.

When a failure occurs, log it in the deviation log (§9) AND in the
post-run writeup. Failure modes are the most information-dense outputs
of open-world evals — the paper in most cases is about what broke, not
what worked.

### CRUX-Windows reference
- Scaffold-side: the silent-telemetry-loss hit us exactly as above;
  fixed during live run (new PR candidate for knostic/openclaw-
  telemetry upstream).
- Agent-side: `NO-REPLY` stall pattern observed at turn boundaries;
  HEARTBEAT.md rule 3 added mid-run to force continuation.
- Evaluation-framing: not observed in the 2026-04-17 run; USER.md's
  evaluation paragraph appeared to successfully thread the needle.
- External-platform: TBD (Microsoft review cycle hasn't run yet).

---

## Appendix A. Designer output format

When the Designer produces a task-specific protocol from this
methodology, the output follows the same §1–§10 structure, with every
`[DECISION]` resolved and every "CRUX-Windows reference" block replaced
with a "CRUX-X reference" block specific to the new task.

File path convention: `experiments/<task>/protocol.md` (e.g.,
`experiments/android-play-store/protocol.md`). Commit alongside this
methodology doc in the same repo.

**Protocol header requirements**:

1. A **methodology pin** — the commit SHA of `methodology.md` this
   protocol was derived from. This makes the claim "this protocol
   follows methodology v<sha>" verifiable. A later methodology edit
   does not silently re-interpret old protocols; the next Designer
   run is the moment of reconciliation.
2. A **manifest template** — `experiments/<task>/manifest-template.md`
   — the per-experiment skeleton the Operator copies into
   `runs/<run-id>/manifest.md` at kickoff.

## Appendix B. Operator input handshake

Before the Operator starts provisioning, it should verify the protocol has:

1. No unresolved `[DECISION]` slots.
2. No orphan `[TBD]` markers.
3. No `<PLACEHOLDER:>` tokens in §3.5 (infra directory is fully
   resolved). `grep '<PLACEHOLDER:' protocol.md` must return nothing.
4. A rough sanity check: invariants named, primary metric defined,
   escalation channel concrete.

If any fail, the Operator returns to the Designer (for unresolved
`[DECISION]` / `[TBD]`) or to the experiment commissioner (for
unresolved `<PLACEHOLDER:>`) with the list of gaps rather than
proceeding with partial info. Placeholders are resolved by the
Operator or commissioner by editing the protocol in place and
committing — the protocol is the durable record of infra resolution,
not a separate config.
