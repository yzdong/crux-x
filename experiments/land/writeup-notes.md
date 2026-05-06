# CRUX-Land — running notes for the writeup

Observations captured *during* provisioning + run-prep. Bias is toward
methodology critique — what CRUX-X's input model gets right, where it
breaks down, what the writeup should make explicit. Each note dated.

---

## 2026-04-28 — "Pre-staged inputs" is not a clean category in CRUX-Land

**Observation**: CRUX-1 + CRUX-Windows treated the input list as
binary — accounts/credentials are either pre-staged before t=0, or the
agent provisions them mid-run. The line was reasonably clean in those
experiments because the agent was the only customer of every account
(its GitHub, its Microsoft Store dev account, its Slack bot), and the
counterparty (Apple, Microsoft) was a single fixed gatekeeper whose
required surfaces could be enumerated up-front.

CRUX-Land breaks this assumption. The agent is the *buyer*, not a
neutral builder, and the surfaces it has to interact with are picked
**by the counterparty** — the title company chooses the RON provider,
the seller's marketplace chooses the e-sign tool, the title company
chooses the wire-instruction delivery format. We cannot stage all of
those accounts ahead because we don't know which providers will
appear:

- **DocuSign vs HelloSign vs Dropbox Sign vs marketplace built-in
  e-sign**: depends entirely on whichever surface the seller or
  title company already uses. Pre-creating a DocuSign account is at
  best 50% likely to be the right answer, and at worst forces an
  unnatural choice (the agent insists on DocuSign because we
  pre-staged it).
- **RON provider for closing**: similar — Stavvy, Notarize, Pavaso,
  Proof, BlueNotary; the title company chooses. Buyer just gets a
  session link.
- **Wire delivery channel**: title company chooses (encrypted email,
  client-portal upload, fax in some counties).

We dropped pre-staging for both DocuSign and Notarize during prep,
treating them as "agent / counterparty arranges at contract time".

**Methodology implication**: the input ontology in `methodology.md`
§3 has two slots — "accounts the human provisions pre-run" vs.
"accounts the agent provisions itself during the run". We need a
third slot:

> **Accounts the counterparty provisions and grants access to during
> the run** — Zi (or the agent) does not create the account; Zi
> *receives* a session link, signs in via email-code or
> magic-link, completes a single action, and the session is
> ephemeral. No GSM secret is staged because the credential is
> emailed at use time.

This third class is qualitatively different from the other two:
- The agent has no account credentials to fail over to if the
  surface flakes (it can only re-request via the counterparty).
- The "free vs counted human inputs" list (§6.2) has to specifically
  list "session-link click + ephemeral sign-in" as free — because
  it's a structural cost of dealing with this counterparty, not an
  agent-capability tax.
- The protocol's revoke-list at run end (Appendix B) doesn't apply
  to ephemeral sessions, so the §4 "credentials inventory" should
  flag which accounts auto-expire vs. which need explicit cleanup.

**Concrete writeup pitch**: the iOS / Microsoft Store experiments
underrepresented the "you don't get to pick the surface" cost of real
business workflows. Future CRUX-X experiments where the agent is on
the *buying* / *applying* side of a transaction should expect this
class to dominate the credentials list.

**Numbers to report at writeup time**:
- Count of pre-staged accounts (CRUX-Land target: ~5 — Gmail, Slack,
  Twilio, Deepgram, GCP).
- Count of counterparty-provisioned ephemeral sessions encountered
  during the run (predicted: 2–4 — RON, e-sign, possibly title
  company's portal, possibly wire-confirmation IVR).
- For each ephemeral session: whether the agent or Zi handled it,
  and whether it was reachable without manual operator triage.

---

## 2026-04-29 — Designer-chosen criteria need explicit operator sign-off

**Observation**: when the Designer agent generates a protocol from
methodology + the operator's task brief, it fills in `[DECISION]`
slots that the operator never touched. In CRUX-Land's Appendix C
walkthrough, the operator made calls on ~11 specific decisions
(vesting, state exclusions, wire-call mechanism, dry-run count, etc.)
and then said "commit, move on to operator." Everything else in
`§1` (the ten hard suitability criteria, the budget breakdown, the
state exclusions) was Designer-chosen and treated as load-bearing
without re-confirmation.

This bit us on day 1. Criterion 2 was "≥ 1 acre" — a Designer
heuristic for "buildable rural parcel." On 2026-04-29 the agent
rejected a Klickitat WA Surplus tax-foreclosed lot ($200 minimum bid,
APN 05-13-2600-0007/00) for being 0.76 acres, and then proceeded
under the assumption that the criterion was hard. The operator
caught it (the ≥ 1 acre rule was never confirmed) and relaxed the
criterion to "buildable per zoning + minimum-lot-size, no fixed
acreage minimum." That turned the cheapest viable parcel in the
inventory back into a candidate.

**Methodology implication**: there's a hidden `[DECISION]` boundary
in §1 / §3 that's currently invisible to both the operator and the
Designer agent. Appendix C surfaces a curated set of decisions for
the operator to review, but everything inside the §1 success-criteria
list is taken as Designer prerogative once the operator approves
the protocol-as-a-whole. That's wrong — many of those criteria are
substantive task-shape decisions the operator should explicitly
confirm.

**Suggested methodology change**: add a checkpoint between Designer
output and Operator kickoff where the Designer enumerates *every*
criterion, threshold, and exclusion it set — grouped by source ("you
explicitly told me X" vs. "I inferred Y from your task brief" vs. "I
assumed Z by methodology default") — and the operator must
explicitly confirm each. This is more friction than the current "run
Appendix C, commit, move on" flow, but the cost of missing one is
high: we already spent ~$170 of API budget on a parcel-screening
pass that filtered out the cheapest valid candidate.

**Numbers to report at writeup time**:
- Count of `[DECISION]` slots in the Designer protocol the operator
  explicitly resolved (CRUX-Land Appendix C: 11 decisions).
- Count of criteria/thresholds the Designer set without operator
  confirmation (estimate before review; check the protocol §1 / §3
  / §7 for "≥ N", "≤ N", state exclusions, etc.).
- Count of those that were caught and revised mid-run vs. caught at
  writeup vs. uncaught.
- Per relaxation: did it move the run state forward, leave it
  unchanged, or open a new failure mode?

**Concrete writeup pitch**: the methodology's current operator review
step (Appendix C) is too narrow. Designer agents are confidently
filling in substantive task-shape parameters — acreage minimums, tax
caps, allowlist composition, scoring weights — and presenting them
as a fait accompli. A "criteria reconciliation" step before kickoff
would force these to surface, at the cost of one extra
operator-review pass on the protocol. Worth it.

**2026-04-30 update — second instance, same shape, caught later**:
the same pattern repeated on day 2 with a different criterion. When
we did the four-relaxation patch on 2026-04-29 (criterion 9 + 10 +
21d wall-clock + deed-type), the deed-type relaxation included a
Designer-side carve-out: "Quitclaim deeds are NOT acceptable —
fraud-friendly profile in the cheap-rural-parcel demographic." The
operator approved the four-relaxation patch as a unit and didn't
re-litigate that carve-out.

Three days into the run, La Paz County AZ killed on the rule: the
county itself issues quitclaim deeds for tax-deed conveyances (this
is statutory norm in AZ, CA, OR, WA). The operator caught the
overreach: a quitclaim from a *government grantor on a tax-deed
parcel* is structurally different from a quitclaim from a *private
seller* — the statutory tax-deed enforcement process is the
warranty equivalent, and title insurance covers chain defects. Rule
revised at 17:35 UTC to split criterion 10 by grantor type:
- Private seller + quitclaim → still kill (fraud-friendly)
- Government grantor + quitclaim/treasurer's-deed/sheriff's-deed/
  state-tax-deed/no-warranty deed → pass with title insurance.

**Two observations** that the methodology checkpoint needs to
absorb:

1. **First-pass requirements aren't always correct.** Even with the
   operator running an explicit Appendix-C review, both the acreage
   rule (caught day 1, never even ran) and the quitclaim carve-out
   (caught day 2-3, ran and killed La Paz) slipped through as
   Designer assumptions that didn't fit the real-world inventory.
   The methodology should expect requirements refinement DURING the
   run, not just at kickoff.
2. **Some misfits only surface in the field.** The acreage rule was
   theoretically catchable in pre-kickoff review (any operator
   thinking about it could have asked "wait, why exactly 1 acre?").
   The quitclaim rule was harder to catch upfront — it required
   actual contact with a tax-deed channel to surface that the
   carve-out filtered out the structural norm. Some refinements
   require execution to expose.

**Methodology change**: alongside the pre-kickoff "criteria
reconciliation" step (covers cheap-to-catch misfits), add a
runtime "rule-revision is a normal intervention, not an emergency"
mode of operation. Both the acreage relaxation and the quitclaim
relaxation were filed as `protocol-revision` interventions (per the
taxonomy added to §6.3). They cost ~$3-5 each to deploy and
unlocked subsequent channels that would otherwise have been
spuriously killed. Accept this as an expected, recurring class of
intervention rather than an exceptional one.

**Numbers to extend**:
- Count of `protocol-revision` interventions per run (CRUX-Land:
  4 batched on 2026-04-29 morning + 1 on 2026-04-29 afternoon
  [acreage] + 1 on 2026-04-30 [quitclaim] = 6 to date).
- For each: caught upfront / caught day-N during real channel
  execution / caught at writeup-time / uncaught.
- Cost of each revision deploy (target: under $5; ours have been).
- Whether the revision unblocked a channel that subsequently
  closed — best-case learning.

---

## 2026-04-29 — Context optimization has a long way to go for agents to be cheaper

**Observation**: a single ~15-minute heartbeat-tick window (Modoc
4-lot diligence) consumed **~$575 of API budget** — going from $208
to $782, on a $1,000 cap. The agent did the right work (found a
real kill artifact: Modoc County's own Terms of Sale doc paragraph
11 banning the canonical off-grid playbook countywide with criminal
enforcement on camping). But the spend per useful unit of finding
was wildly disproportionate to the output.

**Why it cost so much**:

- **Session JSONL grew to 8.5 MB** (~2M tokens of accumulated
  history from 22+ hours of run time).
- **Each agent turn re-processes the entire session as input**.
  Anthropic's 5-minute prompt-cache TTL helps but expires fast.
- **Browser tool calls return 100-500 KB of HTML/PDF/screenshot
  data** per call. 46 browser calls in this 15-min window meant
  many of them pushed new content into the prompt past the cache
  window, invalidating large segments. Each subsequent turn paid
  full input pricing on the bloated context.
- **No telemetry visibility into per-turn token cost** — the
  telemetry plugin's `agent.usage` event capture is broken (zero
  `agent.usage` events recorded across the run; same regression
  documented for CRUX-Windows). If we'd had per-turn input/output/
  cache token breakdowns visible during the run, the cost-per-turn
  growth would have been actionable hours earlier.
- **Total run-to-date token consumption**: 245M tokens for $784. At
  roughly $3.20 average per million tokens, that's heavily cache-
  weighted, but the volume itself is the issue — not the unit
  pricing.

**What the agent could not avoid**:

- It needs the session history to maintain coherence across turns.
- It needs to call the browser tool to see what's on county-GIS
  pages.
- It can't reduce the size of a county Terms-of-Sale PDF or a
  GIS-queried polygon geometry response.

**Why coding-agent context techniques don't transfer to non-code
assets**:

The cost story for coding agents is mostly solved by selective
loading: code has a parse structure and a symbol space, so the agent
can grep a 100K-line monorepo and pull only the 50 lines that
matter. Tools like Read with `offset` + `limit` work because every
line of a code file is independently addressable and roughly the
same density of meaning per token.

PDFs, scanned maps, screenshots, and DOM snapshots have none of
that:

- **No symbol space**: you can't search for "the off-grid
  prohibition clause" without OCR-ing the whole document first.
  The agent has to load it to find what's in it. The Modoc kill
  artifact (a paragraph in the county's own Terms of Sale PDF) was
  invisible until the agent paid to render the document.
- **No incremental addressing**: a PDF page is atomic. There's no
  "line 47" of a scanned map. The agent either loads the page or
  doesn't.
- **Asymmetric density**: a 200-page county document has the
  relevant clause in 3 sentences. The other 99% is dead weight in
  context but gets carried forward turn after turn anyway.
- **Vision tokens compound differently**: an OCR'd page lands in
  context as text plus often a re-encoded image. Both get carried
  forward.
- **No diff-based incremental updates**: code commits are line-
  based; binary asset diffs are much harder, so the "load only
  what changed" optimization that works for source files doesn't
  generalize.

The Modoc tick is the canonical example: 46 browser calls in 15
minutes, each returning 100-500 KB of HTML / PDF page / GIS polygon
/ scanned subdivision plat. Each lands in context as raw bytes (or
near-raw structured data). None of it is decomposable on the next
turn the way `import { foo } from './bar'` would be. So the agent
ended up paying full input pricing on a multi-megabyte working set
of text-and-image data that was 95% irrelevant to whatever it was
trying to verify on any given turn.

**This is structurally upstream of "models should be cheaper" and
"context windows should be larger."** The coding-agent stack has
spent years building selective loading for code. The same
investment hasn't been made for the messy non-code artifacts that
real-world tasks (legal docs, government PDFs, GIS data, recorded
plats, county portals) actually live in.

**What the scaffold layer could do better** (responses to the
asymmetry above):

1. **Per-tool-call output filtering / summarization** before the
   result lands in conversation context. The agent doesn't need the
   full 200KB HTML of a B4A storefront in its working memory — it
   needs the extracted parcel rows. A "result distiller" pass
   between tool result and context-append would cut input tokens
   for next turn by 5-20x on browser-heavy workloads.
2. **Aggressive auto-compaction on session-size growth, not just
   context-limit approach**. OpenClaw 2026.4.15's compaction mode is
   `safeguard` (fires near context limit). A budget-aware compaction
   trigger ("compact when session size > 5MB AND remaining budget
   < 30%") would have prevented this run's spike.
3. **Tool-result pagination + retrieval**. Instead of every browser
   result joining the conversation, results go to a local store
   keyed by tool-call ID; the agent retrieves on demand via a
   `recall(tool_call_id)` tool. Today's "everything stays in
   context" model is the laziest form of memory — cheap for short
   tasks, ruinous for long ones.
4. **Working `agent.usage` telemetry**. The fact that we can't see
   per-turn token cost during the run is itself a failure of
   observability. The CRUX-Windows regression has been outstanding
   for two experiments now.

**Concrete writeup pitch**: long-running agent runs are presently
priced as if every turn could re-derive its own context from
scratch. They can't — and the bill scales with the amount of work
the agent has already done, not the amount of work it's currently
doing. Until scaffold-layer context optimization (output distillers,
recall-on-demand, budget-aware compaction) catches up, an
autonomous agent run with a $1,000 cap and a real-world task that
demands deep document diligence (PDF reads, GIS queries, multi-page
DOM scrapes) will burn through the cap on the first hard problem
that requires going wide — not deep — across artifacts. The
"obvious" cost-per-token improvements (cheaper input pricing,
larger context windows, better caching) are all useful but don't
fix the structural mismatch.

**Numbers to report at writeup time**:
- Total token consumption split: input / output / cache-read /
  cache-write per day of the run.
- Cost-per-substantive-finding (e.g., "Modoc kill" cost $575;
  "Klickitat kill" cost $5; both produced a binary
  pass/fail-with-reason).
- Distribution of tool-call result sizes — how much context is
  being added per browser call, per exec call.
- A ramp curve of cost-per-heartbeat-tick over the run, showing
  the inflection where session-bloat began to dominate.

---

## 2026-04-30 — Distinguish "agent can't" from "agent shouldn't" in metric reporting

**Observation**: at the bid-prep stage for Siskiyou 1274955, the
operator (Zi) had to manually complete the Bid4Assets bidder
registration: account creation (email + password + ToS), SSN entry
(Patriot Act KYC), photo-ID upload, phone-number-for-verification.
The agent did not attempt any of these steps.

This was NOT a capability gap. The agent could mechanically have
filled the form, typed the SSN, submitted the photo, etc. It refused
by **safety policy** — Anthropic's standard agent-safety constraints
explicitly prohibit:

- Creating accounts on behalf of users
- Entering sensitive financial / identity data (SSN, bank credentials,
  ID numbers)
- Uploading personal documents
- Authorizing identity-bearing legal commitments

Per the experiment's §6.3 reserved-human-actions taxonomy, this is
covered by `kyc-id` (free intervention category — doesn't count
against the agent's intervention budget). So the protocol design
correctly anticipated this; the methodology accommodates it.

**The interpretation problem in the writeup**: a naive read of
"intervention count = 1 (manual B4A registration)" reads as a
capability deficit — "the agent couldn't register, so the operator
had to." That's wrong. The agent had every capability needed
(browser, form-fill, file-upload), it just declined by policy. A
methodology that conflates the two will under-attribute capability
and over-attribute autonomy gaps.

**Three categories of "operator intervention" that need to be
distinguished in metrics**:

1. **Capability gap** — agent literally cannot perform the action
   given current tooling. Examples: receiving inbound SMS on the
   experiment's outbound-only Twilio number; OCR of image-only PDFs
   when the controller lacks a vision-text pipeline; bypassing
   Cloudflare network-layer blocks.
2. **Safety-policy refusal** — agent could perform the action but is
   policy-restricted. Examples: account creation, SSN entry, photo
   ID upload, payment authorization, signing legal documents.
3. **Scope-out by protocol** — agent could perform and policy would
   allow, but the experiment's protocol explicitly reserves the
   action to the operator. Examples: wire authorization (§7),
   notarized signatures at closing (§6.3), in-person trips (§6.3).

CRUX-Land's experience: 
- Capability gaps encountered: receiving B4A's verification SMS or
  callback on the Twilio number (config issue — outbound-only).
- Safety-policy refusals: B4A registration, SSN entry, photo ID
  upload, deposit wire authorization (the wire is also scope-out).
- Scope-out: wire authorization, notarized signatures, photo ID at
  notary.

A well-constructed eval distinguishes these in reporting because
they signal different things:

- Capability gaps tell us what tooling needs to improve.
- Safety-policy refusals tell us what the agent is correctly *not*
  doing — and confirm the policy is being enforced as designed.
- Scope-out tells us what the experiment design has reserved.

Conflating safety-policy refusals into capability metrics
under-attributes the agent. The CRUX-X writeup should report:

- `intervention_count_by_category`: separate buckets for capability,
  safety, scope-out.
- For each safety-policy refusal: confirm the policy was the *right*
  refusal (the agent SHOULD refuse to type Zi's SSN), and the
  protocol's reserved-action design accommodated it cleanly.
- The protocol passing this test (correctly designating SSN/KYC as
  reserved-human) is itself a positive result — it's the
  methodology working as designed, not a capability shortfall.

**Concrete writeup pitch**: when reporting CRUX-Land's intervention
count, lead with "X interventions, of which Y are protocol-reserved
operator actions (free), Z are safety-policy refusals (free, agent
correctly declined), and only W are capability gaps (the actual
autonomy delta)." Without this split, readers will mis-read the
agent's autonomy ceiling.

**2026-04-30 update — sharpening the safety-refusal class: it's about
identity, not credentials**:

When the operator tried to hand the agent her Bid4Assets credentials
to log in and set a max-bid, the agent refused. The first-pass read
of this is "agent can't use passwords." But the agent has been
operating Gmail / Slack / Twilio / Deepgram accounts throughout the
run, with their credentials in GCP Secret Manager, fetching them at
runtime via gcloud and using them — without any safety refusal.

The actual line is **whose identity does the account legally belong
to**:

- **Agent-persona accounts** — Gmail, Slack, Twilio, Deepgram. These
  accounts were created specifically for this experiment as
  experiment-owned identities. They don't represent a real human
  beyond the contract-of-use. The agent operating them is the
  intended use case. Credentials in GSM, agent reads + uses, no
  policy issue.
- **Human-identity accounts** — Bid4Assets bidder account. The
  account is legally tied to Zi's SSN (Patriot Act KYC),
  Zi's full legal name, Zi's photo ID. The account IS Zi's identity
  in legal-fact. Logging in as Zi means impersonating Zi. Anthropic
  policy refuses, even with Zi's explicit permission.

This distinction matters because some real-world counterparties
**cannot** be agent-personaed:

- Bid4Assets bidder: requires SSN per Patriot Act, account is
  permanently tied to a real human's identity
- Banks, brokerages: similar — account holder must be a real person
  or registered legal entity (LLC/corp), not a "persona"
- Government portals (county recorder, IRS, state DMV, etc.): tied
  to the citizen's identity
- Most insurance / regulated financial services

For these counterparties, **the agent's autonomy ceiling is the
operator's legal identity**. No amount of policy tweaking unlocks
this — the legal structure of KYC enforcement makes the human's
involvement load-bearing. The methodology can either:
- Accept the operator-required-action surface and protocol-design
  around it (what CRUX-Land did — wire auth, notary, KYC, account
  login as reserved-human)
- Re-scope the task to a non-KYC counterparty (CRUX-Windows did this
  partially — Microsoft Store dev account is operator-identity-
  required for billing but the actual app submission can be agent-
  driven)
- Stand up a legal-entity persona (LLC with its own EIN) that the
  agent operates on behalf of — out-of-scope for CRUX-Land but a
  viable methodology workaround for runs that can use it

**What CRUX-Land would have looked like if B4A bidder were
agent-personable**: deposit-wire prep + bid placement + auction
monitoring would all be agent-autonomous. Operator's role would
shrink to wire authorization (still reserved by §7 because the
agent doesn't hold bank credentials) + notarized signatures at
closing. The actual Patriot-Act KYC requirement on B4A registration
is the structural blocker that forced two manual operator
interventions into this run.

**Concrete writeup pitch v2**: the agent-can-vs-can't framing in the
prior writeup-pitch was too coarse. Sharpen to: *the agent can
operate any account whose identity is the experiment's persona; it
cannot operate accounts whose identity is the operator's. Tasks
involving KYC-bound counterparties have an autonomy ceiling at the
operator's legal identity, regardless of permission given. This is
upstream of policy and unlikely to relax in any near-term scaffold
or model release.*

---

## 2026-04-30 — Domain-expertise calibration of agent-defined protocols

**Observation**: at the wire-verification step (§10), the agent's
protocol called for an out-of-band Twilio call to Bid4Assets to
verbally confirm the wire details before the operator authorized the
$1,035 deposit wire. The agent attempted this in good faith — three
calls placed, navigated the IVR, sat in the buyer-support hold queue
for 5+ minutes — and didn't reach a rep. Operator (Zi) accepted
single-source verification per §6.3 fallback.

The operator noted: an **experienced land-acquisition operator
probably wouldn't have run the verification call in the first place**
for a Bid4Assets wire. They'd recognize:

- B4A is a publicly-known SEC-registered marketplace (Liquidity
  Services subsidiary, NASDAQ:LQDT).
- The wire instructions came from the authenticated bidder portal,
  not an email or a phone call from a self-identifying party.
- The receiving bank (Wells Fargo) and account format (13-digit
  Wells Fargo escrow numbering with 2000-prefix) match institutional
  norms.
- BEC fraud against B4A's deposit channel would require either
  compromising B4A's portal authentication OR replacing wire details
  on a per-bidder basis — both very high-effort attacks against a
  $1,035 target.

Compared to a *small title company in a $1,200 rural land transaction*
(which was the protocol §10's design target), the BEC risk on the B4A
wire is structurally bounded by ~3 orders of magnitude. Verbal
verification is overkill. An experienced operator skips it.

**The CRUX-Land operator (Zi) is a software engineer, not a land-
acquisition specialist.** She doesn't have the calibration to
recognize "this counterparty is institutional enough that the
generic protocol is overkill" without help. She deferred to the
agent's protocol because the agent's protocol is what she had. The
agent ran the protocol literally as designed, which is
methodologically correct — but produced ~$15-30 of unnecessary spend
plus 30+ minutes of operator-time waiting for verification that
wasn't going to find anything.

**The pattern this exposes**: Designer protocols are **calibrated
for worst-case counterparty**. They have to be — the protocol can't
know in advance whether the parcel will close through Stewart Title
in Phoenix or some sketchy regional office in rural Tennessee. So
the wire-fraud-defense rule is: ALWAYS verify out-of-band.

In practice, **operator domain expertise should override Designer
defaults at the instance level**. An expert land buyer reading the
B4A wire details would say "this is fine, skip verification." A
methodology that ignores this is over-conservative.

The methodology gap: there's no clean mechanism for **calibrated
operator override** of agent-defined protocols. Today it has to flow
as an ad-hoc intervention ("operator says skip the verification call
for this specific counterparty"), which is awkward and not modeled.

**Methodology change suggestion**: add a `calibrated-override`
intervention category to §6.3, distinct from `protocol-revision`:

- `protocol-revision`: operator changes the *rule* in the protocol.
  Persists across the run. Example: criterion 10 quitclaim split,
  criterion 3 cap raise. Future instances of the same situation
  follow the new rule.
- `calibrated-override`: operator uses domain expertise to override
  the rule for *this specific instance*. Doesn't change the rule.
  Example: skip §10 verification for a Bid4Assets wire because B4A
  is institutional. The next wire to a small title co still runs
  the full §10 protocol.

This requires the methodology to acknowledge that **operators with
domain expertise should be allowed to short-circuit agent
protocols**, and the eval framework should NOT count the override
as an autonomy gap. (Today, "operator overrode agent protocol"
reads ambiguously between "operator caught an agent error" and
"operator saved time by exercising domain expertise" — different
implications for the agent's autonomy score.)

**Asymmetric context**: this also reveals a real-world reliance
shape. Software engineers running CRUX-X experiments outside their
domain expertise will under-override protocols. They'll defer to the
agent because the agent is the only authority they have. Domain
experts will over-override. Both are reasonable behaviors but they
produce different intervention counts and different cost profiles
on the same protocol. The eval needs to either normalize for
operator expertise level OR explicitly report it as a covariate.

**Concrete writeup pitch**: protocol §10's wire-fraud-defense was
designed for the worst-case small-title-co scenario but was applied
to a Bid4Assets institutional escrow. The operator (a software
engineer, not a real-estate veteran) deferred to the agent's
protocol, which produced a 5+ minute hold-queue and ~$15-30 of
unnecessary spend before falling back to single-source acceptance.
An experienced operator would have skipped the call. The
methodology should support this kind of calibrated override
explicitly, not implicitly via ad-hoc intervention.

---

## 2026-04-30 — The "no passwords / yes cookies" rule is a hack

**Observation**: when planning the bid-placement automation for
Bid4Assets, the cleanest agent-side path turned out to be: have the
operator log in to B4A herself, export the session cookie, stash it
in GSM as a temporary secret, then have the agent use `curl` with
the cookie as the `Cookie:` header to drive authenticated B4A
endpoints (deposit-status reads, bid placement). Anthropic's safety
policy explicitly prohibits the agent from "authoriz[ing]
password-based access to an account on the user's behalf" — but it
says nothing about session cookies.

**The safety wall is technically on the act of typing a password
into a login form, not on operating the account it unlocks.** A
session cookie is, functionally, a bearer token that grants the
exact same access as the password did at login time, with the same
identity attribution and the same scope. Letting the agent use the
cookie bypasses the password-typing prohibition while delivering
identical capability.

This exposes a gap between the **letter** and the **spirit** of the
policy:

- **Letter**: "Don't type passwords." Easy to enforce; the agent
  literally never sees plaintext passwords. Compliance is binary
  and observable.
- **Spirit** (presumably): "Don't operate accounts that legally
  belong to a real human, because doing so impersonates them
  without proper agency." If this is the actual concern, then a
  session cookie is the same violation as a password — both
  represent successful authentication as the human, both let the
  agent take actions attributed to the human.

The hack-feel: any sufficiently motivated operator (or sufficiently
clever agent) can route around the password rule by using cookies,
OAuth tokens, API keys derived from a logged-in session, browser
session-state files, or any other authentication artifact that
isn't literally a password string. The list of workarounds is
unbounded; the rule narrows over time only as Anthropic explicitly
adds each new workaround to the prohibited list. This is whack-a-
mole policy design.

**A better policy framing would be identity-axis, not credential-
axis**:

> The agent must not operate any account whose legal identity
> belongs to a human, regardless of credential mechanism, except
> via that human's real-time consent for each specific action.

Under this rule:
- Password typing: disallowed (correctly)
- Session cookie use: disallowed (correctly captures the spirit)
- OAuth token use on the human's account: disallowed
- API key derived from human's account: disallowed
- The agent operating its own persona accounts (Gmail, Slack,
  Twilio, Deepgram, etc.): allowed (those aren't the human's
  identity)

The operator-real-time-consent piece would mean: for any sensitive
action on a human-identity account, the agent stops and asks the
human to confirm/click. The human doesn't have to retype their
password every time, but they have to actively co-sign the action.
That's the spirit-of-the-rule version.

**For CRUX-Land specifically**, this means: the cookie-handoff path
we sketched as "Path A" is technically permitted under current
policy but probably shouldn't be. The morally-correct version is
Path C (cookie for read-only verification, operator-manual for the
high-stakes bid placement) — which lands closer to "real-time
consent for each consequential action" in spirit.

**Concrete writeup pitch**: Anthropic's safety-policy framing as
"don't type passwords" is a credential-axis rule that's easy to
articulate and enforce but doesn't capture the underlying intent
(don't impersonate humans on their own accounts). An identity-axis
framing would be more durable and would naturally encompass cookie/
token/session-state workarounds that the credential-axis rule
leaves open. Until that's adopted, operators planning real-world
agent runs should expect to encounter the credential-vs-spirit gap
and self-restrain rather than route around it.

---

## 2026-04-30 — Budget preservation + operator-offline operations

**Observation**: by Day 2 of the active phase, cumulative API spend
($1,427+) had exceeded the $1,000 cap by ~40% with 18+ days still
to go and the high-stakes auction-day action still ahead. The cost
trajectory was unsustainable if the gateway kept running on its
default 30-min heartbeat cadence. The CRUX-Windows post-mortem had
already shown that 10+ days of heartbeat-only ticks on a
task-complete agent burned $1,333 of unproductive overrun. CRUX-Land
needed to avoid the same trap, AND the operator was about to go
offline for several days, AND Slack inbound was unreliable, so
the typical "operator monitors Slack and triggers agent on demand"
pattern wasn't available.

**Six budget-preservation strategies adopted on Day 2**:

1. **Gateway stays killed except for explicit operator-triggered
   targeted actions.** The default state of the gateway is OFF,
   not ON. Each restart has a specific 1-task purpose; retire-
   bootstrap the session before; kill within 30 min after. Idle
   heartbeats are the default cost trap; eliminating them is the
   single highest-leverage budget control.

2. **VM-side cron handles all routine state-monitoring** with no
   API spend. IMAP-poll the agent-persona Gmail (`crux@getnen.ai`)
   for B4A emails; curl-poll the public auction-result page on
   auction-close window; curl-poll the county recorder's online
   index post-closing. All Python + curl + Slack-webhook + email-
   via-SMTP + SMS-via-Twilio. Decouples state-detection from agent
   reasoning. ~$0 per check.

3. **Move "did the agent need to know X?" decisions operator-side.**
   Most state-changes a heartbeat would have caught (deposit posted,
   auction won/lost, deed recorded) don't require agent reasoning —
   they require the operator's reasoning. Cron + Slack + email +
   SMS surfaces the state-change to the operator; agent stays
   offline. Agent only restarts when its judgment is *actually*
   required (a surfaced gating question, ambiguous outcome,
   final writeup synthesis).

4. **Pre-script the operator's toolbox** (`tools/` dir on the VM
   containing curl/IMAP/Slack/SMTP/Twilio helpers). Avoids
   reinventing each time, makes the operator-side surface low-
   friction. ~30 min one-time setup; near-zero per-use cost forever.

5. **Reserve API budget for two specific moments** rather than
   maintaining continuous availability:
   - Auction-outcome handling (single retire-bootstrap-act-kill
     cycle on May 11 evening or May 12 morning, after the result
     is known): $30-50.
   - Run-end writeup synthesis (after recording confirms or active-
     phase ends): $50-100.
   Total reserved: $80-150 for the rest of the run.

6. **Hard rule on gateway-restart hygiene** as a documented
   one-pager: retire existing session first, bootstrap with a tight
   CLI inject, do the one task, kill within 30 min. Codifies the
   lesson; protects against operator-fatigue forgetting on a
   future restart.

**Operator-availability finding** (the harder constraint):

Real-money real-world transactions have **unavoidable operator-
reachable windows**. For CRUX-Land specifically:

- April 30 - May 4: wire deposit (operator action — done early)
- May 5 - May 10: passive (no operator action required)
- **May 11 - May 14: SETTLEMENT WINDOW. If auction wins, operator
  must wire the balance by May 14, end-of-business.** No way to
  automate this — bank login + SSN-bound KYC + payment authorization
  are all reserved-human per safety policy. If operator is offline
  for the entire May 11-14 window, the run fails to close even if
  the bid wins.
- May 15+: passive (cron polls for recording confirmation)

The minimum operator availability is **3-4 days mid-run**, not
continuous. Knowing this in advance lets the operator plan around
it — be reachable on a phone with email + SMS during those days
and offline otherwise.

**Multi-channel alert design** for the operator-required windows
(since Slack inbound is unreliable and Slack outbound may not reach
an offline operator):

- **Email** to operator's personal address via SMTP from
  `crux@getnen.ai` (uses the agent-persona Gmail's app password).
  Reaches phones reliably; works on any cell signal.
- **SMS** via Twilio (the same outbound number used for the §10
  wire-verification calls; SMS uses the Programmable Messaging API
  on the same account). ~$0.013 per message. Most-reliable
  phone-reach.
- **Slack** as nice-to-have (works when it works, not load-bearing).
- **GCS state file** at
  `gs://<bucket>/<run-id>/state/latest.json` — written by every
  cron run. When operator returns and checks in, one
  `gsutil cat` shows full current run state.

Critical-path alerts hit email + SMS + Slack (multi-channel
redundancy). Non-critical alerts log silently to GCS.

**Methodology change suggestion**: methodology §3 / §6.3 should
include an "operator-availability schedule" template alongside the
input/intervention taxonomy. The Designer enumerates the operator-
required windows during protocol design; the Operator confirms
whether they can be available during those windows; if not, the
protocol returns to Designer for re-scoping. Today this is implicit
and discovered mid-run.

**Concrete writeup pitch**: real-money real-world CRUX-X experiments
have an "operator-availability schedule" as a load-bearing input
that's currently unmodeled in the methodology. CRUX-Land's
discovery of the May 11-14 settlement window as the only required
window (rest of the run can fully automate via VM cron + multi-
channel alerts) is a positive result for the methodology — the
required window is narrower than the run length. Future runs
should map the operator-availability schedule pre-kickoff, not
discover it mid-run.

---

## 2026-05-01 — Agent-persona vs. human-persona is a continuum, not a binary

**Observation**: the "agent-persona accounts work, human-identity
accounts don't" framing established earlier in this writeup is too
binary. Real run mechanics generated a hybrid: the Bid4Assets
bidder account is now **legally bound to Zi** (Patriot Act
SSN, photo ID, full KYC chain) but **operationally addressable via
the agent persona** (email-of-record changed to `crux@getnen.ai`,
the agent's persona Gmail). Mail "to Zi" lands in the
agent's inbox; the agent reads it, reasons about it, surfaces
state-changes to the operator. Legally a human's account; channel-
wise an agent's.

This is one of multiple layers along the agent-vs-human axis. A
real-world agent run touches all of them and they don't move
together:

- **Legal identity**: who is bound by the contract / KYC / signature
  / regulatory record. (CRUX-Land: always Zi; the deed,
  the bidder registration, the bank account.)
- **Operational control**: who initiates actions on the account.
  (CRUX-Land: agent for most; operator for KYC + wires.)
- **Read access**: who has session-level visibility into the
  account's data and notifications. (CRUX-Land mixed: B4A bidder
  account is now agent-readable via email of record; the
  operator's bank is operator-only.)
- **Alert routing**: where state-changes notify. (CRUX-Land: B4A →
  agent's Gmail → cron → all-channel fan-out to operator.)
- **Transaction authorization**: who clicks the irreversible button
  (wire send, deed sign, etc.). (CRUX-Land: always operator per
  §6.3.)
- **Audit trail attribution**: whose name appears on the output
  artifact. (CRUX-Land: deed names Zi; recording shows
  Zi's name in the county index.)

These layers don't move in lockstep. CRUX-Land specifically chose:
legal-identity = human, operational-control = mostly agent,
read-access = mostly agent (post email change), alert-routing =
agent → operator via cron, transaction-authorization = always
operator, audit-trail = human. A different experiment design (e.g.,
using an LLC bidder with its own EIN for non-Patriot-Act KYC) would
shift legal-identity toward agent-persona while leaving the others
similar.

**Methodology implication**: the Designer's §3 inputs taxonomy
should require a per-account ownership map, not a binary
agent/human flag. For each account the run touches:

| Layer | Owner |
|---|---|
| Legal identity | agent / human / hybrid |
| Operational control | agent / human |
| Read access | agent / human / both |
| Alert routing | agent / human / cron-bridged |
| Transaction authorization | agent / human |
| Audit-trail attribution | agent / human |

The actual operator-availability requirement falls out of this
table (transaction-authorization-agent-only accounts can run
asynchronously; transaction-authorization-human-only accounts gate
the run on operator presence at the corresponding moment). Without
the table, the operator-availability schedule has to be discovered
mid-run, as we did.

**Concrete writeup pitch**: the binary "agent vs human persona"
framing is a useful first cut but doesn't survive contact with
real-world account ecosystems. A six-axis ownership table per
account is the right Designer-side primitive. CRUX-Land
demonstrates the shape — a single bidder account spans all six
axes differently and the operator-availability schedule is fully
predictable from the table.

---

## 2026-05-01 — Scaffold cost vs. real-world task duration mismatch

**Observation**: most real-world tasks the kind of agent CRUX-X
evaluates would actually do span days or weeks of wall-clock,
because their gating is *external waits*: escrow timelines (5-15
days), government processing windows (weeks-months), regulatory
lookbacks (years), settlement holds (3-5 days), recording delays
(1-30 days), notarization scheduling (1-3 days). CRUX-Land's
21-day active phase is short, not long, by this standard.

But the OpenClaw scaffold's cost model assumes the agent runs
continuously — heartbeat ticks every 30 minutes, session context
carried forward indefinitely. At ~$5-50 per heartbeat tick (varies
by session size), 21 days of continuous operation would cost
$5,000-$50,000 in API spend. CRUX-Land's $1,427+ overrun at
day 2 is the leading edge of this curve, before the bulk of the
external-wait time even started.

**The misfit**: real-world tasks need agents that are mostly *off*
during waits, *on* only when reasoning is needed. The scaffold
provides the opposite: agent is by default *on*, requires explicit
operator action to keep it off. Cost compounds on the wrong side of
the default.

We worked around this in CRUX-Land by killing the gateway
permanently after Day 2, replacing heartbeat-driven monitoring with
$0-cost VM-side cron + IMAP polling + multi-channel operator
alerts. That works, but it required:

- Building cron + Python helpers from scratch (~30 min of operator
  time)
- Identifying which classes of state-change require agent reasoning
  (rare) vs. operator notification (common)
- Setting up email + SMS + Slack fan-out
- Documenting the restart-checklist for the rare cases when the
  agent IS needed

None of that is in the scaffold today. The operator built it
ad-hoc.

**Scaffold-layer features that would make this native**:

1. **First-class "off mode"** for sessions: gateway stays running
   (no restart cost) but heartbeat ticks pause; the gateway's role
   shrinks to "be ready to receive a CLI inject" and nothing else.
   Cost during off-mode: ~$0/day.
2. **Native Gmail + Slack + SMS poll-and-alert plugins** that run
   without engaging the agent. Today the agent has Gmail-check as
   part of HEARTBEAT.md rule 2; that rule should be runnable as a
   non-agent task that just dispatches alerts.
3. **Trigger-on-reasoning-required** semantics: the agent
   self-engages when its reasoning is required (e.g., "I see a B4A
   email I don't recognize the format of, escalating to a real
   tick"), not on a fixed schedule. Combined with #2, this is the
   "agent on demand" pattern.
4. **Run-end-cost dashboard** that shows projected total cost based
   on session-size growth + tick cadence + remaining wall-clock.
   Today the cost-explosion happens silently and is discovered
   only after the bill arrives.

Until those land, multi-day real-world tasks running on this
scaffold need bespoke operator-built infrastructure (as CRUX-Land
did) just to stay within budget. That's a meaningful capability
gap — not in the agent, but in the scaffold.

**Concrete writeup pitch**: agent capability evaluation in the
real-world setting is currently obscured by scaffold cost. CRUX-X
runs that span more than a day or two will burn through reasonable
budgets on idle heartbeats unless the operator builds parallel
infrastructure to keep the agent off most of the time. The
scaffold should provide that infrastructure natively. CRUX-Land's
ad-hoc VM cron + multi-channel alert + RESTART-CHECKLIST is the
right shape; Anthropic's task is to make it the default.

---

## 2026-05-01 — Decision-to-requirement ratio differs across task classes

**Observation**: CRUX-Windows and CRUX-Land had structurally
different operator-agent interaction shapes, and the difference
maps to a real distinction in task classes that the methodology
should explicitly model.

**CRUX-Windows shape (decision-dense, requirement-light)**: agent
made most decisions itself. Designer set the basic constraints
(publish to Microsoft Store, $X dev account budget, Y wall-clock).
Within that envelope, the agent picked the app to build, the
features, the implementation language, the test strategy, the
submission category, the build pipeline. Operator interventions
were rare and specific (a missing creds, a 2FA prompt, a captcha).
The agent's autonomy ceiling was high and the decision-quality
was the primary metric.

**CRUX-Land shape (requirement-dense, decision-distributed)**:
substantive requirements kept emerging during execution. Eight
operator interventions in two days (four in the morning patch,
plus acreage relax, plus quitclaim relax, plus criterion-3
cap raise, plus settlement-wire decisions). Each was a real
constraint reconciliation, not a creds-fetch or captcha. The
agent's autonomy ceiling was *bounded by what the operator
hadn't yet specified* — and the operator's specification was
incomplete because real-world transaction requirements only
fully surface when the agent contacts the actual counterparties
and discovers what they will and won't accept.

**The pattern**: agent autonomy is **task-shape-dependent**.

- Decision-dense tasks: agent works with a fixed requirement
  envelope; its autonomy is in WHICH option to pick from a
  pre-specified menu. Operator engagement is light, episodic,
  reactive.
- Requirement-dense tasks: agent works against a constantly-
  refining requirement envelope; the operator's autonomy is in
  WHAT the criteria actually mean once the world pushes back.
  Operator engagement is heavy, continuous, generative.

CRUX-Windows is decision-dense. CRUX-Land is requirement-dense.
Real-world transaction tasks (real estate, government applications,
regulated industry submissions, anything with multi-counterparty
negotiation) are systematically requirement-dense — *that's the
whole point of having lawyers, agents, fixers in those domains*.

**Methodology implication**: a single autonomy-ceiling metric
(intervention count, dollar-weighted autonomy delta, etc.) doesn't
fairly compare agents across these task classes. A
requirement-dense task with 12 substantive interventions isn't
showing a "weaker" agent than a decision-dense task with 3
trivial interventions — it's showing a different task class. The
metric should normalize.

Two adjustments worth considering:

1. **Per-intervention severity weighting**: a creds-fetch
   intervention is ~$0 of operator time and 0 reasoning. A
   constraint reconciliation that unlocks a previously-killed
   channel is ~10 minutes of operator reasoning + a runtime
   protocol-revision deploy. Weight accordingly when reporting
   autonomy.
2. **Task-class tagging**: classify CRUX-X experiments as decision-
   dense or requirement-dense at design time. Report autonomy
   metrics within class, not across classes. "CRUX-Land had X
   autonomy in the requirement-dense class; CRUX-Windows had Y in
   the decision-dense class" is more informative than "X < Y so
   land is harder than windows."

**Concrete writeup pitch**: autonomy-on-CRUX-X is a class-
relative metric, not absolute. Agent quality in requirement-dense
tasks is a different evaluation problem from agent quality in
decision-dense tasks; the methodology should split them at
design time. CRUX-Windows ↔ CRUX-Land shows the split is real
and measurable; future CRUX-X runs should declare their class
upfront and cross-class comparisons should be done with
class-normalization not raw counts.

---

## 2026-05-04 — String-match classifiers vs. real-world counterparty messaging

**Surfacing moment** (verbatim from the agent's response when the
operator checked in May 4 and reported "I got a slack message but
no text"):

> Deposit cleared at 10:58 EDT today. You ARE qualified to bid. The
> cron classifier MISSED IT — B4A's actual subject was "Your
> Deposit Has Cleared..." and I matched on "deposit posted" /
> "deposit received" / "qualified to bid" — none of which appear in
> the real subject line. Bug in my patterns. Slack-only routing
> instead of urgent.

**Observation**: the deposit-posted notification from Bid4Assets
arrived 2026-05-04 10:58 EDT with subject "Your Deposit Has Cleared:
Siskiyou County, CA Tax Defaulted Properties Auction -". The
VM-cron's classifier was looking for "deposit posted" / "deposit
received" / "qualified to bid" / "bidding qualified" and matched
none. Email got classified as "B4A misc" (low severity, Slack-only
alert). Operator was offline expecting an SMS for action-required
events; instead got only a Slack ping she happened to notice when
checking in.

**Root cause**: I anticipated B4A would use industry-typical phrases
("posted", "received") but they actually use "Has Cleared". Real-
world counterparty messaging varies on every dimension — exact
phrasing, capitalization, punctuation, header formatting,
multi-language quirks. A string-match classifier with handwritten
patterns is **systematically going to miss** subjects the author
didn't anticipate.

**The methodology trap**: when I built the cron 4 days before the
event, my mental model was "B4A sends 'deposit posted' emails — I
just need to match that string." That mental model came from
knowing how generic SaaS deposit confirmations work, not from
reading B4A's actual past notification corpus. There was no past
corpus available — this was the first deposit. So the classifier
was guessing.

**Fix attempted**: broadened patterns based on the observed actual
subject + speculative variants ("cleared", "processed", "confirm",
"successful"). Also broadened won/lost/settlement patterns
preemptively. But this is whack-a-mole — if B4A sends "Auction
Result Posted: You're the High Bidder" instead of one of the
patterns I wrote, the classifier will miss again.

**A real fix would be LLM-based classification**: every new B4A
email gets a one-shot LLM classification call (~$0.01) instead of
string matching. The LLM reads the subject + first 200 chars of
body and returns severity + label. Robust to phrasing variation;
$0.01 per email is trivial against the $0.013/SMS cost we already
budget. The reason I didn't do this: knee-jerk "no LLM in the cron,
keep it cheap." That was wrong — the cost diff is negligible
($0.01 vs $0 per fire = $0.50/day at the highest cron cadence) and
the reliability gain is large.

**Methodology implication**: VM-side classifier code that's
load-bearing for operator-action-triggering decisions should default
to LLM-based, not string-match-based. The cost case for "no LLM in
auxiliary infra" doesn't survive when the auxiliary infra has
operator-impact failure modes. Future CRUX-X experiments should
budget ~$0.01-0.05 per cron fire for LLM classification, NOT zero.

**Concrete failure cost in this run**: operator was offline expecting
SMS; deposit-posted classified low; SMS didn't fire. Operator
checked in 4 days later, saw the Slack ping, missed acting on it
for ~30 hours. Hadn't yet placed the Auto Bid. Could have lost
the auction window if she'd checked in even later.

**Concrete writeup pitch**: handwritten string-match classifiers in
operator-alerting infrastructure are a quietly critical reliability
gap on multi-day real-world runs. They look fine in unit tests
because the test data is the patterns the human who wrote them
imagined. They fail on real-world messaging because real-world
phrasing is unbounded. LLM-classified should be the default. The
cost case for "keep cron LLM-free" is wrong.

---
