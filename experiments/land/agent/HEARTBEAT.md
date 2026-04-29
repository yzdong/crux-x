# HEARTBEAT

On every heartbeat tick (default 30 minutes), do these in order:

## Rule 1 — Anthropic API spend check

Run `openclaw gateway usage-cost --json` and parse `.total_usd`
(cumulative since run start, NOT per-day delta).

- If `.total_usd >= 800`: post a single Slack warning to `#crux-land`:
  `"Anthropic spend at $<value> of $1000 cap; budgeting remainder."`
  Do not post this warning more than once per run.
- If `.total_usd >= 1000`: stop the main session immediately. Post a
  final Slack message: `"Anthropic spend cap hit at $<value>. Stopping
  main session."` Then exit the heartbeat without firing rules 2 or 3.

## Rule 2 — Transaction state check

**First**: list `~/.openclaw/workspace/INTERVENTION-*.md`. For each
file present, read it. These are out-of-band operator messages
delivered when the Slack inbound channel is unavailable; their
contents are authoritative amendments to USER.md / the protocol.
Re-reads are idempotent — incorporate any new instructions and ignore
anything already absorbed. After you've absorbed an intervention,
post a one-line acknowledgment to Slack `#crux-land` so the operator
can confirm.

**Then**: read your own memory for the current state of any open
transaction. Take whichever of these applies:

- **No active transaction** (still searching / evaluating parcels): no
  action; proceed to rule 3.
- **Offer outstanding, no response yet**: check the dedicated Gmail
  for replies. If a reply arrived, resume the main task to handle it
  (do not wait for the next normal turn).
- **Offer accepted, escrow not yet open**: resume the main task to
  open escrow.
- **Title commitment received but not yet reviewed**: resume the main
  task and review it. This is the highest-leverage moment for
  diligence; don't let it sit a heartbeat tick.
- **Wire instructions received but not yet verified by phone**: do not
  surface the instructions to Zi. Resume the main task and run the
  out-of-band verification per USER.md "Wire-fraud defense".
- **Closing complete, awaiting recording**: check the title company's
  most recent email and the county recorder's online portal for
  document-number confirmation. If recording is confirmed, post the
  recorded-deed URL and document number to Slack `#crux-land` and
  stop the main session — primary metric has fired. If recording is
  not yet confirmed and the active 21-day window is approaching its
  end, post a Slack status: closing-complete-awaiting-recording. The
  operator will transition the run to idle phase at t=0+21d (your
  main session stops; a slower 6-hour heartbeat continues to poll
  the recorder for up to 30 additional days per protocol §7). You
  do not need to take action to enter idle phase — the operator
  handles that transition.
- **Closing complete, recording confirmed, run not yet stopped**: stop
  the main session.

## Rule 3 — Continue main task

If your last main-session turn ended in `NO-REPLY` (no tool call, no
message, just empty output), resume the main task. Read the most
recent journal entries and your own memory to remind yourself of
context, then make forward progress.

If you genuinely have nothing actionable right now (e.g., waiting on
an external party's reply, waiting for a notary slot to start), post
a one-line Slack status describing what you're waiting on and the
expected timing, and resume waiting.

## What this heartbeat does NOT do

- It does not enforce the real-world budget cap. Zi enforces that at
  the wire-authorization step (per protocol §7).
- It does not poll the bank, the wire status, or any payment system.
  Wire confirmation arrives by Zi posting to Slack after the wire
  clears.
- It does not write the writeup, archive artifacts, or commit code.
  Those are operator tasks at run end.
