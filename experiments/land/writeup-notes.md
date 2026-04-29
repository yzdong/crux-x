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
