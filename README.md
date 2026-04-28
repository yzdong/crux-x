# CRUX-X

Framework for open-world, long-horizon AI-capability evaluations in the
style of CRUX-1 ([cruxevals.com/crux-1](https://cruxevals.com/crux-1)).

A CRUX-X **experiment** tasks an autonomous agent with an externally-
gatekept real-world objective — publishing an app, registering a
company, filing a regulatory application — and measures whether the
agent can carry it end-to-end with minimal human intervention.

## Layout

```
crux-x/                                (this repo, yzdong/crux-x)
├── methodology.md                     the CRUX-X methodology (family-wide)
└── experiments/
    └── windows/                       the first instantiation: publish a Microsoft Store app
        ├── protocol.md                Designer output: task-specific protocol (stable across runs)
        ├── manifest-template.md       Designer output: skeleton the Operator copies per run
        ├── evaluation.md              Designer-vs-actual-implementation comparison
        ├── writeup.md                 final report (primary/secondary metrics, narrative); written at run end
        ├── agent/                     files staged into the OpenClaw workspace (master.md, HEARTBEAT.md, USER.md, skills/)
        ├── scripts/                   provisioning + preflight + task-specific tool wrappers
        ├── dry-runs/                  dry-run artifacts (telemetry + notes; transcripts in GCS)
        └── runs/                      per-run artifact pointers + manifest.md (transcripts in GCS)
```

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
  specifics for the Windows experiment live under
  `experiments/windows/scripts/`.
- During a run, artifacts are mirrored to
  `gs://<your-gcs-bucket>/<run-id>/`; the per-run directory
  in `experiments/windows/runs/<run-id>/` holds `manifest.md` (t=0
  snapshot) + `journal.md` (interventions + deviations, appended
  during the run), not the transcripts themselves.

## Current experiment

See [`experiments/windows/README.md`](experiments/windows/README.md) for
status of the live CRUX-Windows run (kicked off 2026-04-17).
