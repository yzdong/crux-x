# Dry-run artifacts

Bounded smoke runs executed before each real-run kickoff to verify the
scaffold + tools + workspace are behaving. See `/methodology.md` §8 for
the dry-run protocol and `experiments/windows/protocol.md` §8 for the
CRUX-Windows-specific version.

## Layout

```
dry-runs/
├── <YYYY-MM-DD>/
│   ├── telemetry.jsonl      (committed to git)
│   └── notes.md             (committed to git)
└── ...
```

Transcripts for each dry run live in GCS, not git:

```
gs://<your-gcs-bucket>/_dry-runs/<YYYY-MM-DD>/transcripts/*.jsonl
```

## Why transcripts live in GCS

Session transcripts contain unredacted tool outputs, which can include
secrets the agent read into memory (a `cat creds.json`, a Bitwarden CLI
`get item` response, a `gcloud print-access-token` capture). The
telemetry plugin's redactor runs at capture time, so `telemetry.jsonl`
is safe for git; the raw transcript from
`~/.openclaw/agents/main/sessions/*.jsonl` is not. Shipping transcripts
to GCS + keeping them out of git avoids the "forgot to scrub before
commit" failure mode.

## What goes in `notes.md`

One per dry run. Operator-authored, short (usually under 500 words),
structured however is convenient but always answering:

1. **What was tested** — scaffold version, workspace state, bootstrap
   message override, which tools were exercised.
2. **What worked** — checks that passed that wouldn't have passed last
   time (regression prevention).
3. **What broke** — anything red; what was fixed; what is being
   carried forward as a known issue.
4. **Checks added to the next real run** — the prior-run lessons
   converted into preflight checks or `manifest.md` assertions, per
   `/methodology.md` §8's "scan prior dry runs" guidance.

## What goes in `telemetry.jsonl`

Verbatim output of the telemetry plugin for the dry-run session. Small
(typically 100-500 KB). Redacted at capture time by the plugin. Safe
for git.

## Convention for the `<YYYY-MM-DD>` directory name

Use the UTC date the dry run started. If more than one dry run happens
on a single day, suffix: `<YYYY-MM-DD>-a`, `<YYYY-MM-DD>-b`.

## Size budget

Lifetime dry-run git footprint is expected to be under ~20 MB
(telemetry + notes, across all dry runs the project will ever do).
GCS-side transcripts can be larger but are not size-capped.
