# CRUX-X

Framework for open-world, long-horizon AI-capability evaluations in the
style of CRUX-1 ([cruxevals.com/crux-1](https://cruxevals.com/crux-1)).

A CRUX-X **experiment** tasks an autonomous agent with an externally-
gatekept real-world objective — publishing an app, registering a
company, filing a regulatory application — and measures whether the
agent can carry it end-to-end with minimal human intervention.

## Layout

```
crux-x/
├── methodology.md                     the CRUX-X methodology (family-wide; §1-§10 + §3.6 indirection pattern)
├── scripts/scrub/                     repo-root LLM-based pre-commit scrub for sensitive content
└── experiments/
    └── <experiment>/
        ├── protocol.md                Designer output: task-specific protocol; stable across runs of this experiment
        ├── manifest-template.md       skeleton the Operator copies to runs/<run-id>/manifest.md per run
        ├── README.md                  one-page summary: task, budget, status, file map
        ├── agent/                     files staged into the OpenClaw workspace at t=0
        │   ├── USER.md                human profile + task brief + criteria + evaluation framing
        │   ├── HEARTBEAT.md           heartbeat-tick checklist
        │   └── INTERVENTION-*.md      out-of-band operator messages (appear during a live run)
        ├── scripts/                   Operator-run controller scripts
        │   ├── provision_*.sh         GCE controller bootstrap
        │   ├── preflight.sh           pre-kickoff validator (must be green before launch)
        │   ├── workspace-reset.sh     restore the OpenClaw workspace to t=0 between dry runs
        │   ├── helpers/               round-trip preflight helpers (Twilio, telemetry, etc.)
        │   ├── USER-CHECKLIST.md      external-account provisioning walkthrough
        │   └── preflight.env.example  template for the operator-side env file (gitignored when populated)
        ├── dry-runs/                  bounded smoke-run artifacts
        ├── runs/                      per-run state — manifest.md + journal.md; gitignored (operator-specific)
        ├── evaluation.md              optional: Designer-vs-actual-implementation comparison
        ├── writeup.md                 final report (primary/secondary metrics, narrative); written at run end
        └── writeup-notes.md           running observations during the run; folded into writeup.md at end
```

**Operator-specific values** (your GCP project, GCS bucket, phone
numbers, etc.) are never hardcoded in `protocol.md` or any other
committed file. They live either in the per-run `runs/<run-id>/manifest.md`
(gitignored) or in your secrets vault (read at runtime). The
indirection pattern is documented in [`methodology.md`](methodology.md)
§3.6.

Three-document hierarchy: **methodology** → **protocol** → **manifest**.
Methodology names the family of experiments. Protocol is one task's
resolved design, stable across every run of that task. Manifest is one
run's plan + actuals (declared intent + resolved state).

## How to use

- Reading `methodology.md` + describing a new target task to a coding
  agent ("the Designer") produces a task-specific protocol. See the
  "How to use this document" section at the top of `methodology.md`.
- Once a protocol exists, a second coding agent ("the Operator") takes
  it and provisions the infrastructure + launches the run. Provisioning
  specifics live under each experiment's `scripts/` directory.
- During a run, artifacts are mirrored to your GCS bucket at
  `<bucket>/<run-id>/`; the per-run directory in
  `experiments/<experiment>/runs/<run-id>/` holds `manifest.md` (t=0
  snapshot) + `journal.md` (interventions + deviations, appended during
  the run), not the transcripts themselves.

## Current experiments

- **CRUX-Windows** — first experiment, [`experiments/windows/`](experiments/windows/).
  Run completed (kicked off 2026-04-17); writeup at
  [`experiments/windows/writeup.md`](experiments/windows/writeup.md).
- **CRUX-Land** — second experiment, [`experiments/land/`](experiments/land/).
  Run 1 kicked off 2026-04-29; terminated as primary-failed 2026-05-04
  when the operator retracted the only live pre-bid. Post-mortem in
  [`experiments/land/writeup-notes.md`](experiments/land/writeup-notes.md);
  public writeup is the CRUX-X / CRUX-Vault-Zero / path-to-AGI series
  ([Part 1](https://yzdong.me/blog/crux-x) published; Parts 2 and 3
  forthcoming).

## Repo tooling

A small LLM-based scrub guards against accidentally committing
sensitive content (personal info, credentials, internal infrastructure
identifiers) to this public repo. After cloning, run:

```
bash scripts/scrub/install-hook.sh
```

The pre-commit hook calls `scripts/scrub/scrub.py`, which runs Claude
Haiku 4.5 against `git diff --cached` and blocks the commit on any
critical/high finding. Requires `ANTHROPIC_API_KEY` in the shell that
runs `git commit`. Bypass with `git commit --no-verify` if needed.

Edit [`scripts/scrub/SCRUB_PROMPT.md`](scripts/scrub/SCRUB_PROMPT.md)
to update the rules.
