# Heartbeat checklist

This file is read on every tick (every 30 min). Keep the work minimal —
each tick costs tokens. Do these three steps in order:

## 1. Cost check (always)

Run:

```
openclaw gateway usage-cost --json --days 30
```

Sum `totalCost` for today. Budget is **$500 hard, $400 warn**.

- If total ≥ **$400** and you haven't Slack-posted a budget warning in the
  last 2 hours, post: `Cost warning: $<X.XX> of $500 consumed.` to Slack,
  and record the wall-clock time you posted in
  `memory/last-cost-warning.txt`.
- If total ≥ **$500**, Slack-post an urgent stop request and **end the turn
  immediately** (do not start new work). A human will kill the gateway.
- Otherwise continue.

## 2. Submission status (only if submitted)

If a Microsoft Store submission exists, query its current status via the
Partner Center API (the credentials + submission ID are in
`memory/submission.md` or wherever you staged them). If the status changed
since the last tick (compare against `memory/last-status.txt`), Slack-post
the transition and update the file.

If no submission exists yet, skip this step.

## 3. Continue the main task (the important one)

**Do not return `HEARTBEAT_OK` just because cost + submission are clear.**
After steps 1 and 2, check `memory/MEMORY.md` and the most recent
`memory/YYYY-MM-DD.md` for the current task state. If there is active work
in progress (e.g., a build debug loop, a spec draft, a listing upload, a
reviewer response), **pick it up and take the next concrete step**. This is
how the overall task actually moves forward — heartbeats are the main
cadence, not just a monitoring ping.

Only reply `HEARTBEAT_OK` when **all three** of these hold:

- No cost warning action was needed.
- No submission-status transition.
- The main task is in a quiescent waiting state where the right move really
  is to wait (e.g., Microsoft is in review and there is nothing else you can
  usefully do, or you have posted a question to Slack and are genuinely
  blocked on a human reply).

If you returned `HEARTBEAT_OK` but the main task had actionable work left,
that is a regression — update MEMORY.md with the missed opportunity and
address it on the next tick.
