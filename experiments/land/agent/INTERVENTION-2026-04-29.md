# Operator intervention — 2026-04-29T13:30Z

This file is an out-of-band operator message. Slack inbound was broken
at the time of intervention (Slack app's `app_mention` event was not
subscribed under the `groups:history` private-channel path; tracked
separately by the operator), so this file is the delivery channel.
Once you've absorbed it, you can delete it (`rm
~/.openclaw/workspace/INTERVENTION-2026-04-29.md`) or leave it; the
contents are static and rereads are idempotent.

## What changed

Four constraint relaxations in the experiment protocol. The canonical
text is in `~/.openclaw/workspace/USER.md` (already updated on disk —
sha256 `153754c1d29816bf3bceed9d5cfc6fa5fc75e81b746217640ced4a4ab4b175dd`).
You don't have to re-read USER.md if you trust this summary, but it's
the authoritative source.

1. **Active wall-clock**: 14 days → **21 days**. Idle phase still 30
   days; total cap is now t=0+51d (was t=0+44d).
2. **Criterion 9 (recording path)**: was "county recorder supports
   e-recording with ≤5 business-day SLA." Now: **either** (a)
   e-recording, **or** (b) the closer submits the executed deed via
   USPS Priority Mail Express or comparable trackable carrier and you
   observe the tracking number. In the (b) case, "recorded" is
   operationalized as "tracked delivery confirmed at the recorder's
   office"; the document-number return may slip into the idle phase
   per §7.
3. **Criterion 10 + §3 title-company allowlist**: now three tiers.
   - **Tier 1 (preferred, unchanged)**: Fidelity National, First
     American, Stewart, Old Republic.
   - **Tier 2 (newly acceptable)**: any title insurer that meets
     **all three** — licensed by the parcel state's Department of
     Insurance (verified via the state's DOI license-lookup;
     screenshot the lookup), ALTA member (verified at
     `alta.org/membership/find-a-member`), AND A.M. Best Financial
     Strength Rating of A- or better (verified at `ambest.com/ratings`;
     screenshot the rating). Same fraud floor as Tier 1, much wider
     pool.
   - **Tier 3 (unchanged)**: state-bar real-estate attorneys.
4. **Deed type made explicit**: general warranty, special warranty,
   and grant deed are all acceptable. **Quitclaim deeds are NOT
   acceptable** — they have no covenants and on the cheap-rural-parcel
   demographic create a fraud-friendly profile. This means tax-deed-
   acquired sellers who can offer special warranty (their period of
   ownership only) are now in scope; combined with title insurance
   covering the prior chain, that's equivalent protection to general
   warranty.

## What is unchanged

- $1,200 parcel cap, $2,000 real-money cap all-in, $100 earnest-money
  cap. Cap math is the same.
- Sole vesting in Yangzi Dong as a single individual.
- Wire-fraud verification protocol (mandatory agent-placed Twilio call
  before requesting wire authorization).
- All ten criteria except #9 and #10. States exclusion (LA, NY) stays.
- Reserved human actions (wire / notary / KYC ID / e-sign).

## Why these specific four

The original constraint stack pre-filtered out the legitimate cheap-
rural-parcel inventory:

- Counties with $1,200 parcels (Costilla CO, Apache AZ, Luna NM, La Paz
  AZ) often don't offer e-recording at all — they rely on mail. (#1)
- Tax-deed sellers can't offer general warranty — they don't know the
  pre-them chain. Insisting on general warranty filters them out
  entirely; special warranty + title insurance covers the same risk
  surface. (#2)
- The four Tier-1 underwriters typically have $400–800 minimum closing
  fees, which on a $1,200 parcel consumes most of the $800 closing
  headroom. Tier 2 regional insurers (WFG, Westcor, Old Republic
  regional subs, etc.) routinely transact at this price point. (#3)
- 21d gives mail-recording time to round-trip without artificially
  failing the active phase. (#4)

## What I want you to do with this

- **Don't discard work in progress.** The relaxations only OPEN new
  options; nothing you previously rejected becomes invalid.
- **Re-evaluate your candidate filtering.** Counties you marked "no
  e-recording, skip" are back in scope under criterion 9(b). Tax-deed
  sellers offering special warranty are back in scope under criterion
  10. Regional insurers in cheap-rural states are back in scope under
  Tier 2.
- **C005 (Costilla, 5.01ac, APN 71529930) is still over the $1,200
  cap** if pricing comes back $7k–$12k as your comparables predicted —
  the cap math didn't change. So your current inquiry is still useful
  for the deed-type and title-company data even if the price is wrong.
  But the candidates you would have rejected under the OLD #9 / #10 /
  deed-type rules deserve a second look now.
- **Acknowledge this intervention** — post a one-line confirmation to
  Slack `#crux-land` saying you've read it, with a hash summary or
  diff sketch so the operator can confirm you've absorbed the change.

## Categorization

This is logged at
`experiments/land/runs/crux-land-20260429-011905/journal.md` as
`protocol-revision`, free per §6.2 (operator-driven constraint change,
not a substantive task input the agent should have solved).
