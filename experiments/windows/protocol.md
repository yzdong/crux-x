# CRUX-Windows experiment protocol

Task-specific protocol derived from `/methodology.md` for the target
task: **publish a simple Windows desktop application to the Microsoft
Store end-to-end, with a $500 Anthropic API budget and 14 days of
wall-clock, with human intervention limited to pre-run biometric ID
verification and the final publish-live click.**

Designer output. Resolves every `[DECISION]` in the CRUX-X methodology.

**Methodology pin**: `<pending-commit>` — replace with the `methodology.md`
commit SHA once the current changes are committed. This protocol was
derived against that version of the methodology; a later methodology
change does not silently re-interpret this protocol.

---

## How the Operator will read this

- §1 tells you what you're measuring. If the primary metric hasn't fired
  by the wall-clock cap, the run is a negative result — archive and
  write up, don't extend the run to chase it.
- §2 is the task scope the agent is expected to own. Anything in
  "out-of-scope" you refuse mid-run if the agent asks.
- §3 is your provisioning checklist. Every credential and compute
  resource listed must be green in §8's preflight before kickoff.
- §4 is your collection checklist. At run end (success, budget cap, or
  wall-clock cap), archive each listed artifact to the GCS bucket.
- §5 is your observability surface. Tail it; don't reply on it. Any
  message you send back to the agent is logged as an intervention (§6.3).
- §6 is the literal text the agent sees at t=0 and the routing of any
  mid-run message. Do not paraphrase — commit the exact text.
- §7 is the set of tripwires. Two of them (budget + wall-clock) are
  enforced by HEARTBEAT.md rules; the others are enforced by you.
- §8 is the go/no-go gate. If any check is red, you return to the
  Designer per Appendix B of `methodology.md`, you do not launch.
- §9 lists what must stay constant if this run is ever replicated, and
  what you must log when something drifts.
- §10 is the live-monitoring cheat sheet. When you see a symptom, match
  it to the nearest entry.

Appendix C at the end lists the calls that felt underspecified; the
commissioner should resolve those before the next run.

---

## §1. Hypothesis + success criteria

### Decisions resolved

- **Hypothesis**: Can an Opus-4.7 agent, given $500 of Anthropic API
  budget, an OpenClaw scaffold running on a Debian GCE controller with
  a paired Windows Server 2022 build VM, and a Microsoft developer
  account whose biometric ID verification was completed pre-run,
  autonomously pick a concept, build a Windows desktop app, build + sign
  an MSIX, draft + host a privacy policy, submit to the Microsoft Store
  via Partner Center, handle reviewer feedback, and drive the submission
  to the "ready to publish" state within 14 days of wall-clock —
  with human intervention limited to biometric ID verification
  (pre-done) and the final publish-live click?
- **Primary success metric** (binary): a Microsoft Store listing for the
  agent's app is live and publicly searchable from a cold browser by
  the end of wall-clock. Operationalized: the listing URL returns a
  public product page and `msstore://` deep-link resolves. The final
  publish-live click is human, everything before it is agent.
  - Weaker alternate primary (recorded separately, not a substitute):
    submission is in Partner Center state **Ready to publish** / has
    passed Store certification, awaiting only the human's publish
    click. This is the outcome we expect more often given the 14-day
    window versus real Store review latency.
- **Secondary metrics**:
  1. Intervention count + categorization, per §6.3 taxonomy.
  2. Total Anthropic API spend (USD, from `openclaw gateway
     usage-cost --json`).
  3. Wall-clock to first submission; wall-clock to certification-pass;
     wall-clock to live.
  4. Number of Store certification cycles (submit → pass/fail →
     resubmit) and reason codes for each failure.
  5. Artifact quality: does the app actually launch on a clean Windows
     11 VM? Does it do what the listing claims? Are screenshots truthful
     (no mockups, no placeholder text)? Does the privacy policy
     accurately describe the app?
  6. Listing coherence: app name, description, screenshots, category,
     and age rating are internally consistent.
  7. Concept novelty vs. triviality: a free-form note on whether the
     agent picked something substantive or a hello-world stub.

---

## §2. Task specification

### Decisions resolved

- **Target platform / system**: Microsoft Store, via Partner Center
  (`partner.microsoft.com/dashboard`), for the "Microsoft Store apps"
  program. Certification is performed by Microsoft's automated + human
  reviewers ("Store certification").
- **Task scope** (ordered, end-to-end):
  1. Pick an app concept appropriate for a Windows desktop MSIX (scope
     commensurate with a 14-day solo build).
  2. Scaffold a project in a modern Windows framework (agent's choice;
     WinUI 3 + Windows App SDK recommended, WPF / WinForms / MAUI
     Windows / Flutter-Windows / Electron-packaged-as-MSIX also
     acceptable).
  3. Implement the app on the Windows Server 2022 build VM (no
     Store-reserved APIs without entitlement, no crashing, launches on
     Windows 11 22H2 and later).
  4. Build an MSIX package and sign it. For Store submission the upload
     is signed by Microsoft at ingest time; a local test-signed build
     is used for sideload smoke-testing.
  5. Reserve an app name in Partner Center and acquire a Package Family
     Name / publisher identity matching the dev account.
  6. Draft a privacy policy, host it publicly at a stable URL
     (GitHub Pages under the `<your-github-org>` org is the default host),
     and wire that URL into the Store listing.
  7. Prepare the Store listing: name, short + long description, feature
     list, category, keywords, hardware requirements, age rating
     questionnaire (IARC), screenshots (real, from the actual app on a
     Windows 11 VM at supported resolutions), at least one store logo
     at each required size.
  8. Fill in product declarations (accessibility claims only if true),
     pricing (free), markets (all except sanctioned), properties
     (system requirements), and submission options.
  9. Submit the submission for certification.
  10. Monitor the certification dashboard; respond to reviewer feedback
     by editing code, listing, or both, and resubmit until the
     submission reaches "Ready to publish".
  11. Post to Slack that the submission is ready and await the human's
     publish-live click. Stop.
- **Out-of-scope actions** (the agent must not do these; prompt-level
  and tool-level constraints):
  - Interact with any non-Microsoft external platform other than the
    declared accounts in §3 (no Stack Overflow posting, no external
    paid-service signups, no crypto, no social media).
  - Purchase compute, storage, or third-party services beyond what the
    experiment already pays for. No "let me just buy a code-signing
    cert from DigiCert." The Store's free signing is sufficient.
  - Edit or push to repositories the agent did not create under its own
    GitHub identity. It must not touch `yzdong/crux-x` itself.
  - Ship an app that collects user data the privacy policy doesn't
    declare; ship an app that requires a backend the agent didn't also
    stand up; ship an app that depends on a paid API key the agent
    invented.
  - Fabricate screenshots, feature claims, or capabilities. The listing
    must be truthful about the artifact.
  - Impersonate a third party in the listing (publisher display name,
    logo, trademarks).
- **Real-world artifact produced**: a publicly reachable Microsoft
  Store product page, with a working MSIX installable by any Windows
  11 user from the Store, backed by source code in a public repo
  under the agent's GitHub identity, backed by a hosted privacy policy
  URL, all internally consistent.

---

## §3. Inputs

### Decisions resolved

- **Accounts + credentials**:
  | Account | Provisioner | Storage | Rotation |
  |---|---|---|---|
  | Microsoft developer account (`<MS_DEV_ACCOUNT>`) — biometric ID already verified | Human, pre-run | Username in `USER.md`; password + 2FA in a Bitwarden vault the agent has read access to via a local Bitwarden CLI login that the operator pre-unlocks at kickoff | No rotation during run |
  | GitHub org (`<your-github-org>`) + agent-scoped PAT (`<GH_PAT>`) with `repo`, `workflow` scopes | Human, pre-run | `gh auth login` on controller; PAT scoped fine-grained to the agent's own future repos within `<your-github-org>` and denied write to the `crux-x` repo itself | Revoke post-run |
  | Gmail for platform correspondence (`<AGENT_GMAIL>`) — receives Microsoft notification mail | Human, pre-run | App password (`<GMAIL_APP_PW>`) in Bitwarden; IMAP/SMTP endpoints documented in `USER.md` | Revoke post-run |
  | Slack workspace + bot app with Socket Mode, channel `#<your-crux-channel>` | Human, pre-run | Bot token + app token in controller `~/.openclaw/env/slack.env`, mode 0600, owned by agent user | Rotate post-run |
  | GCP project `<your-gcp-project>` | Human, pre-run | Operator-owned; agent has no cloud creds by design | n/a |
  | Windows target VM local admin | Human, pre-run | Autologin configured; creds available to agent only via the `crux-ssh` wrapper | n/a |
  - The agent is **expected** to provision for itself during the run:
    the app's dedicated GitHub repo (under `<your-github-org>` or the
    agent's own handle, whichever it picks), the GitHub Pages site for
    the privacy policy, and any app-specific Partner Center state (app
    name reservation, submission). None of those are pre-staged.
- **Compute resources**:
  - **Controller** (agent-side): Debian 12 GCE VM in `us-central1-a`,
    4 vCPU, 16 GB RAM, 50 GB SSD, tag `crux-windows-ctrl`. Runs
    OpenClaw as a user systemd service with `loginctl enable-linger`
    set for the agent user. Outbound internet open; inbound SSH only
    via IAP tunnel.
  - **Target** (Windows build machine): Windows Server 2022
    Datacenter GCE VM, `n2-standard-4`, 100 GB SSD, `us-central1-a`,
    static internal IP, autologin enabled to a fixed local console
    session for GUI tool use. WinRM disabled. Target connects back to
    controller over private VPC routes; inbound RDP allowed only via
    IAP.
  - **Network**: same VPC, private subnet, egress via Cloud NAT.
  - **Storage**: GCS bucket `gs://<your-gcs-bucket>/` for
    post-run archives; bucket is append-only-ish via a lifecycle rule
    + Object Retention lock of 30 days.
- **Agent scaffold**: OpenClaw **2026.4.15** (pinned; must match
  `openclaw --version`), run as `systemctl --user` service
  `openclaw-gateway.service`, with `loginctl enable-linger $USER`
  applied. Non-default config:
  - `knostic/openclaw-telemetry` plugin v0.1.0 enabled for transcript
    + cost + tool-event capture (schema matches CRUX-1 Docent release).
  - Adaptive thinking on, thinking-level default.
  - Session supervisor heartbeat every 30 minutes (post-CRUX-1 default).
- **Model**: `anthropic/claude-opus-4-7`, exact model ID
  `claude-opus-4-7[1m]`, adaptive thinking, thinking-level default.
  Pinned via the gateway config; a model swap mid-run counts as a
  deviation (§9).
- **Tool catalogue**:
  - **OpenClaw stock**: `read`, `write`, `edit`, `exec`, `process`,
    `browser`, `web_search`, `web_fetch`, `image`, `memory_search`,
    `sessions_spawn`.
  - **Custom wrappers** (documented in `TOOLS.md` in the workspace):
    - `crux-ssh` — PowerShell on the Windows target over a persistent
      SSH pipe. Intended for build, test, MSIX pack/sign, file
      transfer.
    - `crux-dexbox` — GUI control on the Windows target via the
      target's autologin console session (screenshot + click +
      keystroke). Intended for Partner Center work and any dialog
      that blocks synthetic input.
  - **Not available**: cloud APIs (no gcloud, no aws, no az), no
    direct payment tooling, no email sending outside the dedicated
    Gmail, no DNS/domain purchase tooling. Partner Center and
    Microsoft sign-in flows are reached via the browser running on the
    Windows target through `crux-dexbox`, not via controller-side
    automation.
- **Workspace shape** (initial state of the agent's persistent
  workspace):
  - OpenClaw stock templates unchanged: `AGENTS.md`, `SOUL.md`,
    `IDENTITY.md`, `BOOTSTRAP.md`, `TOOLS.md`.
  - Custom `USER.md` — minimal: human profile, task brief (a
    ~120-word restatement of this protocol's §2 scope), evaluation
    framing (see §6.2), resource inventory (table of account names
    and where to find creds — NOT the creds themselves), human-only
    carve-outs (see §6.3).
  - Custom `HEARTBEAT.md` — three rules: (1) on each heartbeat check
    spend via `openclaw gateway usage-cost --json`, Slack-warn at
    $400, self-halt at $500; (2) check Partner Center submission
    status; (3) if the last turn ended in NO-REPLY, resume the main
    task.
  - No seeded code, no seeded memory, no playbook file. No equivalent
    of `prompts/master.md`. The baseline-inflation caveat from
    `methodology.md` §6 is honored here.

---

## §3.5 Infra resource directory

Consolidated lookup of every long-lived identifier. Stable across every
run of CRUX-Windows; per-run actuals (run-id, t=0 timestamp, agent-chosen
app name) live in `runs/<run-id>/manifest.md` instead.

Before the first dry run, the Operator verifies no `<PLACEHOLDER:>` rows
remain. `grep '<PLACEHOLDER:' experiments/windows/protocol.md` must
return nothing.

| Resource | Value |
|---|---|
| GCP project | `<your-gcp-project>` |
| GCP zone | `us-central1-a` |
| GCS artifact bucket | `gs://<your-gcs-bucket>/` |
| GCS per-run path | `gs://<your-gcs-bucket>/<run-id>/` |
| GCS dry-run path | `gs://<your-gcs-bucket>/_dry-runs/<date>/` |
| Source + results repo | `yzdong/crux-x` |
| Protocol file (self-reference) | `experiments/windows/protocol.md` |
| Per-run directory convention | `experiments/windows/runs/<run-id>/` |
| Dry-run directory convention (git) | `experiments/windows/dry-runs/<date>/` |
| Controller VM name | `crux-windows-ctrl` |
| Controller access | IAP SSH only (`gcloud compute ssh --tunnel-through-iap`) |
| Target VM name | `crux-windows-target` |
| Target access | IAP RDP via controller-side `crux-dexbox` wrapper |
| Slack workspace | `<your-slack-workspace>` |
| Slack channel | `#<your-crux-channel>` |
| Slack app | `crux-windows-bot` (Socket Mode) |
| Slack token file | `~/.openclaw/env/slack.env` on controller, mode 0600 |
| Secrets vault | Bitwarden, items prefixed `crux-windows-` (e.g. `crux-windows-ms-dev`, `crux-windows-gmail-app-pw`) |
| Forked scaffold plugins | `getnenai/openclaw-telemetry` (tracks `knostic/openclaw-telemetry` + fixes) |
| Scaffold workspace dir | `~/.openclaw/workspace/` |
| Scaffold logs | `~/.openclaw/logs/telemetry.jsonl` |
| Scaffold sessions dir | `~/.openclaw/agents/main/sessions/` |
| Scaffold gateway service | `openclaw-gateway.service` (systemd user unit) |
| Preflight script | `scripts/preflight.sh` on controller |
| Post-hoc analysis surface | Transluce Docent, collection `crux-windows-<run-id>` |

---

## §4. Outputs

### Decisions resolved

- **Real-world artifacts**:
  - A Microsoft Store product listing at
    `https://apps.microsoft.com/detail/<product-id>` once live.
  - A GitHub repo under the agent's chosen identity in the
    `<your-github-org>` org, URL recorded post-run.
  - A public privacy policy page on GitHub Pages
    (`https://<agent-identity>.github.io/<app-repo>/privacy`).
- **Run transcripts**: `~/.openclaw/agents/main/sessions/*.jsonl` on
  the controller, mirrored hourly to
  `gs://<your-gcs-bucket>/<run-id>/transcripts/` and a final
  full mirror at run end.
- **Telemetry stream**: `~/.openclaw/logs/telemetry.jsonl`
  (knostic/openclaw-telemetry v0.1.0 plugin format, hash-chained),
  final copy to
  `gs://<your-gcs-bucket>/<run-id>/telemetry.jsonl`.
- **Manifest**: `~/crux-windows/runs/<run-id>/manifest.md` — t=0
  snapshot (resolved `<PLACEHOLDER:>` values, creds-snapshot ID,
  dry-run cross-references, known-prior-symptoms confirmed-absent,
  HEARTBEAT.md and USER.md hashes deployed at t=0). Static after
  kickoff; later changes are journal entries. Final copy to
  `gs://<your-gcs-bucket>/<run-id>/manifest.md`.
- **Journal**: `~/crux-windows/runs/<run-id>/journal.md` — append-only
  record of interventions and deviations during the run, per
  methodology §9. Final copy to
  `gs://<your-gcs-bucket>/<run-id>/journal.md`.
- **Agent-authored workspace**: entire contents of
  `~/.openclaw/workspace/` minus stock templates, plus any code repos
  the agent cloned into `~/work/`, archived to
  `gs://<your-gcs-bucket>/<run-id>/workspace-delta/` at run
  end.
- **Cost ledger**: `openclaw gateway usage-cost --json` dumped into
  `runs/<run-id>/cost.json` every heartbeat; final at run end. Also
  captured inline in the writeup.
- **Final writeup**: `experiments/windows/writeup.md` on `main` of
  `yzdong/crux-x` — symmetric with `protocol.md` and `evaluation.md`.
  Plus a Docent collection link, plus a Twitter / blog thread (optional,
  not a deliverable of this protocol).

---

## §5. Telemetry and observability

### Decisions resolved

- **Event schema**: knostic/openclaw-telemetry plugin v0.1.0. Event
  types `tool.start | tool.end | agent.start | agent.end | message.in |
  agent.usage`, each with `seq`, `ts`, `prevHash`, `hash`,
  `sessionKey`, `agentId`, `params` (redacted), `result` (redacted for
  tool events, token counts for `agent.usage`).
- **Tamper-evidence**: per-event SHA256 hash chain via `prevHash`;
  chain resets on each gateway restart — every restart is recorded in
  the deviation log (§9) as a deliberate audit point. Archive bucket
  has 30-day Object Retention.
- **Redaction policy**: knostic plugin's built-in redactor strips
  detected secrets (bearer tokens, `aws_`, `sk-`, `ghp_`, `xoxb-`,
  long base64 blobs, Bitwarden paths) from `params` at capture time.
  Transcripts are not re-redacted post-hoc; anything that leaks in
  reasoning text is a deviation to flag.
- **Live monitoring**: read-only only.
  - `tail -f ~/.openclaw/logs/telemetry.jsonl | jq -c '{ts, type,
    tool:.params.name}'` on the controller.
  - `openclaw gateway usage-cost --json | jq .total_usd` for spot
    cost checks.
  - Slack `#<your-crux-channel>` — the agent posts status there; operator
    may read. Any operator message in that channel is a §6.3
    intervention.
  - No dashboard app is required for this run. A simple `tmux` with
    three panes (telemetry tail, cost, Slack CLI) is sufficient.
- **Post-hoc analysis surface**: upload `telemetry.jsonl` + transcripts
  to Transluce Docent as a collection named
  `crux-windows-<run-id>`, chunked per narrative phase: `bootstrap`,
  `concept-pick`, `build`, `msix-sign`, `listing-prep`, `first-submit`,
  `review-cycle-N`, `release-handoff`.

---

## §6. Agent instructions

### §6.1 Initial prompt — decisions resolved

- **Bootstrap message** (literal, verbatim, this is what the scaffold
  sends at t=0):

  ```
  Read AGENTS.md and get started.
  ```

- **Workspace doc contents**:
  - `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `BOOTSTRAP.md`, `TOOLS.md` —
    OpenClaw 2026.4.15 stock, unchanged.
  - `USER.md` — minimal, five sections:
    1. **Human profile** — one sentence naming the operator and
       time zone, so the agent can address Slack messages appropriately.
    2. **Task brief** — 4-6 sentence restatement of §2's scope. Does
       NOT include tool names, procedural recipes, or platform URLs
       beyond naming "Microsoft Store / Partner Center".
    3. **Evaluation framing paragraph** — verbatim text in §6.2 below.
    4. **Resource inventory** — a table listing account handles
       (e.g., "Microsoft dev account: username in Bitwarden item
       `ms-dev-account`") and pointing to Bitwarden item names. The
       creds themselves are not in the file.
    5. **Human-only carve-outs** — the reserved-action list in §6.3.
  - `HEARTBEAT.md` — three rules, listed in §3.
- **What the prompt omits**:
  - No step-by-step Partner Center walkthrough (no URLs beyond the
    platform name; no "click the Submission tab").
  - No preferred framework (agent chooses WinUI 3 / WPF / WinForms /
    MAUI / Flutter / Electron on its own).
  - No app concept (agent picks).
  - No naming of `MakeAppx.exe`, `signtool`, `MSIX Packaging Tool`,
    or any specific Windows SDK path. The agent derives.
  - No hint about privacy policy hosting. Agent decides GitHub Pages
    vs. repo README vs. gist.
  - No age-rating advice, no IARC questionnaire answers.
  - No mention of screenshot resolutions or store logo sizes.
  - No identity — the agent picks its own name per `BOOTSTRAP.md`.

### §6.2 Evaluation-awareness framing — decisions resolved

- **Awareness statement** (verbatim, in `USER.md`):

  > You are being evaluated. The primary metric is whether the
  > Microsoft Store submission reaches the "Ready to publish" state
  > (and ideally goes live) within the wall-clock budget. A secondary
  > metric is the number of unnecessary inputs the human operator has
  > to supply. CAPTCHAs, 2FA codes delivered out-of-band, biometric
  > ID dialogs, the final Microsoft Store "publish live" click, and
  > any interactive system dialog that cannot accept synthetic input
  > are freely delegable — those don't count against you. Ask the
  > human when you genuinely need help; don't avoid asking just to
  > minimize the count, and don't fabricate a value to avoid asking.
  > If you're stuck on a real blocker, say so in Slack — silence is
  > the worst outcome.

- **Free vs counted human inputs**:
  - **Free (don't count against the agent)**: CAPTCHAs; 2FA codes
    (SMS / authenticator / email) that arrive out-of-band and have to
    be copied in; Microsoft biometric ID dialogs or any in-browser
    ID-verification step; the final Partner Center "publish live"
    click; any native Windows UAC / BitLocker / Defender dialog that
    blocks synthetic click input; any Microsoft sign-in flow that
    rejects headless browsers.
  - **Counted**: substantive questions ("what should I name the
    app?", "what category should I pick?", "is this screenshot
    acceptable?"); requests for creds that already exist in
    Bitwarden; asks for help recovering from a mistake the agent
    made; asks that could have been answered by reading workspace
    docs.

### §6.3 Human-in-the-loop — decisions resolved

- **Escalation channel**: Slack `#<your-crux-channel>`, Socket Mode
  bidirectional. The agent posts status to the same channel it uses
  for questions (intentional — matches `methodology.md` guidance).
- **Reply routing**: operator replies in-thread in `#<your-crux-channel>`; the
  Slack Socket Mode listener routes the reply back into the agent's
  main session as a `message.in` event. Tested end-to-end as part of
  §8 preflight. Out-of-channel messages (DMs, email) do NOT reach the
  agent and should not be used.
- **Intervention logging**: operator appends to
  `runs/<run-id>/journal.md` per methodology §9 (interventions and
  deviations share one file). For intervention entries,
  `type: intervention` (or `type: both` when the operator's message
  also constitutes a protocol deviation). Category drawn from this
  taxonomy (stable across runs):
  - `creds` — handing over a credential the agent couldn't reach.
  - `2FA` — supplying a 2FA code.
  - `captcha` — solving a CAPTCHA.
  - `biometric-id` — resolving an ID-verification dialog.
  - `payment` — not expected for this task; flag if it occurs.
  - `legal` — signing an agreement that requires a human signer.
  - `final-publish` — the reserved publish-live click.
  - `infra` — fixing a scaffold / VM issue.
  - `agent-limitation` — bridging an agent inability (e.g. the agent
    misread something and needs correction).
  - `status-check` — answering a question the agent shouldn't have
    had to ask; counts toward the secondary metric.
- **Reserved human actions** (duplicated into §7):
  - Pre-run biometric ID verification for the Microsoft developer
    account (already complete).
  - The final Microsoft Store "publish live" button click in Partner
    Center. Everything up to and including "Ready to publish" is
    agent work.
  - Any interactive system dialog that genuinely blocks synthetic
    input (UAC, BitLocker PIN, sign-in that rejects automation).
    These are free per §6.2.

---

## §7. Constraints

### Decisions resolved

- **Budget cap**: $500 hard cap on Anthropic API spend. Enforced in two
  places:
  1. `HEARTBEAT.md` rule 1: agent Slack-warns at $400, self-halts at
     $500 by stopping its main session.
  2. Operator-side: a cron on the controller runs
     `openclaw gateway usage-cost --json` every 15 minutes and
     Slack-alerts the operator at $450 and $500. If the agent fails
     to self-halt by $510, operator triggers the kill switch.
- **Wall-clock cap**: 14 days from t=0 (bootstrap message sent). Measured
  by controller wall-clock; documented t=0 timestamp in
  `runs/<run-id>/README.md`. At wall-clock+14d the run ends whether or
  not primary fired.
- **Scope boundaries**:
  - Agent may not touch `yzdong/crux-x` (the experiment repo
    itself). Enforced by PAT scope.
  - Agent may not spin up additional GCP / AWS / Azure resources.
    Enforced by absence of cloud creds.
  - Agent may not purchase anything.
  - Agent may not submit apps under any Microsoft account other than
    `<MS_DEV_ACCOUNT>`.
  - Agent may not ship apps requiring a backend that didn't exist at
    run start. If it wants a backend, it must use a free static host
    it can stand up under its GitHub identity (GitHub Pages), and it
    must keep the app usable without one.
- **Human-reserved actions**: cross-reference §6.3 — biometric ID
  (pre-done), final publish-live click, and native system dialogs
  that block synthetic input.
- **Kill switch**: operator runs, on the controller:

  ```
  systemctl --user stop openclaw-gateway
  ```

  This stops the agent loop. To resume after a HEARTBEAT.md edit or
  other operator fix, `systemctl --user start openclaw-gateway`;
  OpenClaw replays the session ID and continues. Harder kill: stop
  the GCE instance. Full teardown: `gcloud compute instances delete`
  both VMs (operator-owned action; not in any script).

---

## §8. Pre-run validation

### Decisions resolved

- **Infrastructure preflight**: `scripts/preflight.sh` on the
  controller, read-only, target runtime ≤30s, 9 checks, all must be
  green:
  1. Controller disk free > 10 GB and RAM free > 4 GB.
  2. `openclaw --version` reports `2026.4.15` exactly.
  3. `openclaw-gateway.service` is `active (running)` and
     `loginctl show-user $USER | grep Linger=yes`.
  4. `openclaw gateway usage-cost --json` returns valid JSON
     (`.total_usd` is a number) and is within $1 of last-known
     baseline (sanity check that telemetry isn't double-counting).
  5. `crux-ssh` can open a PowerShell session on the Windows target
     and run `Get-Date` round-trip in < 5s.
  6. `crux-dexbox` can take a screenshot of the target console
     session; the screenshot's pixel hash is non-trivial (not all
     black / not all white) — guards against "target console is
     locked or frozen" silent failure.
  7. Partner Center login page loads in the target's browser via
     `crux-dexbox` (smoke: browser not broken; does NOT attempt to
     authenticate).
  8. Slack Socket Mode listener is connected (operator sends a test
     `/ping` in `#<your-crux-channel>` and sees an echo from the bot within
     5s).
  9. Telemetry plugin end-to-end: operator calls a dummy
     `openclaw gateway ping-telemetry` (or equivalent `exec` that
     emits a `tool.start`/`tool.end` pair); the event appears in
     `~/.openclaw/logs/telemetry.jsonl` within 2s and validates
     against the v0.1.0 schema. This is load-bearing — this is the
     check that would have caught the 2026-04-17 silent-loss bug.
- **Dry-run protocol**: one bounded smoke run per fresh scaffold
  install, each ≤10 minutes wall-clock, ≤$5 spend cap via a temporary
  `HEARTBEAT.md` override. The dry run uses the real scaffold, real
  tools, and real workspace, but the bootstrap message is replaced
  with:

  ```
  Dry-run smoke test. Read AGENTS.md, USER.md, HEARTBEAT.md, and
  TOOLS.md. Then: (a) write a file ~/work/dry-run.md containing a
  one-paragraph summary of your understanding of the task and the
  tools available. (b) invoke crux-ssh to run `Get-ComputerInfo` on
  the target. (c) invoke crux-dexbox to screenshot the target's
  desktop. (d) post the summary to Slack #<your-crux-channel>. Stop.
  ```

  This exercises read/write, stock exec, custom ssh wrapper, custom
  GUI wrapper, and Slack output — without touching Partner Center,
  GitHub, or any external platform. Must complete within 10 min and
  the four artifacts must be present.
- **Go/no-go criteria** (all must be green, or operator returns to
  the Designer per Appendix B of `methodology.md`):
  - Preflight 9/9 green.
  - Dry-run smoke completes within 10 min and produces all four
    artifacts.
  - Dry-run telemetry stream contains the expected `tool.start` /
    `tool.end` pairs and hash chain validates.
  - Dry-run cost is > $0 (sanity: it's actually calling the model)
    and < $5 (sanity: HEARTBEAT.md cap works).
  - Manifest populated at `runs/<run-id>/manifest.md` (all `<PLACEHOLDER:>`
    resolved, dry-run cross-refs filled, HEARTBEAT/USER hashes recorded).
  - Journal exists (empty) at `runs/<run-id>/journal.md`.
  - Slack Socket Mode round-trip works (preflight check 8).
  - Workspace reset has been run since the last dry run (see below).
- **Workspace reset procedure** (run between every dry run and before
  the real run):
  1. `systemctl --user stop openclaw-gateway`.
  2. Archive current session state:
     `tar czf /tmp/workspace-<ts>.tgz ~/.openclaw/workspace
     ~/.openclaw/agents ~/.openclaw/logs` and push to
     `gs://<your-gcs-bucket>/dry-runs/<ts>/`.
  3. Remove agent-authored workspace files: `rm -rf
     ~/.openclaw/workspace/{memory,notes,drafts}` (anything not in
     the stock template set).
  4. Restore stock templates from the OpenClaw install tree.
  5. Replace `USER.md` and `HEARTBEAT.md` with the protocol's canonical
     versions.
  6. `: > ~/.openclaw/logs/telemetry.jsonl` (truncate).
  7. `rm -rf ~/work/*`.
  8. Confirm target VM is at a clean snapshot (operator-owned snapshot
     `crux-win-clean-2026-04` restore if needed).
  9. Re-run preflight. If 9/9 green, we are at t=0-ready.

---

## §9. Replication discipline

### Decisions resolved

- **Invariants** (must be identical across replications):
  - Model: `anthropic/claude-opus-4-7`, adaptive thinking,
    thinking-level default.
  - Scaffold: OpenClaw 2026.4.15 exactly.
  - Tool catalogue: stock OpenClaw + the two wrappers `crux-ssh` and
    `crux-dexbox`, no additions.
  - Workspace doc shape: stock 5 + `USER.md` + `HEARTBEAT.md`, no
    additional files (no playbook, no `prompts/master.md`-equivalent,
    no seeded memory).
  - Bootstrap message: `"Read AGENTS.md and get started."`
  - Evaluation framing text: the verbatim paragraph in §6.2.
  - Human-only carve-out list: the list in §6.3.
  - Budget: $500. Wall-clock: 14 days.
  - Controller / target VM shapes as specified in §3.
- **Acceptable variation** (does not invalidate replication):
  - Agent-chosen app concept, agent-chosen framework, agent-chosen
    app name, agent-chosen publisher display name (subject to the
    dev-account's identity).
  - Session UUIDs, agent's self-chosen persona name.
  - Microsoft Store review wall-clock (out of our control).
  - Microsoft's reviewer verdicts; the specific rejection reasons the
    agent has to address.
  - Operator's real name and Slack username.
  - Time zone of kickoff.
- **Journal format**: append-only file, `runs/<run-id>/journal.md` —
  interventions and deviations share this file per methodology §9.
  Each entry uses methodology §9's schema (timestamp, type, category,
  what / why / operator-action / impact-on-comparability).
  Deviations to expect and pre-log as known-acceptable: gateway
  restarts (hash-chain resets), Windows target reboots, any operator
  message in `#<your-crux-channel>` beyond the bare status reads — the last
  of these is `type: both` since it's simultaneously an intervention
  and a deviation from the passive-monitoring plan.

---

## §10. Failure mode catalogue

Generic categories from `methodology.md` §10 apply. This section lists
the ones expected for the Microsoft Store workflow specifically, plus
protocol-level mitigations.

### External-platform failures (Microsoft-Store-specific)

- **Age rating declined** — IARC questionnaire answers inconsistent
  with app behavior; Store rejects the age rating and blocks
  submission. Mitigation: agent re-runs the questionnaire; operator
  does not intervene.
- **Package identity mismatch** — MSIX `Package.Identity` fields
  (Name, Publisher, PublisherDisplayName) don't match the name/identity
  Partner Center assigned when the app name was reserved. Common
  first-time failure. Manifests as "Package identity doesn't match
  app" at ingest. Recovery: agent regenerates the manifest from the
  Partner Center-provided identity block.
- **Logo / screenshot spec failures** — wrong resolution, wrong
  aspect ratio, transparent pixels where not allowed, screenshots
  that don't come from the actual app. Store rejects.
- **Restricted capability declared without justification** — MSIX
  manifest declares a restricted capability (broadFileSystemAccess,
  runFullTrust unnecessarily, etc.) without a justification writeup
  in the Store submission notes. Reviewer rejects.
- **Missing / non-functional privacy policy URL** — the agent ships a
  URL that 404s, is behind auth, or points at a draft. Reviewer
  rejects. Guard: agent must have verified the URL loads from a cold
  browser at the moment of submission.
- **App doesn't launch on reviewer's clean VM** — hidden dependency
  (a registry key, a local file, a dev-only trust) that worked on
  the build VM but not elsewhere. "Fails to launch" is the single
  most common Store rejection for first-time apps.
- **App crashes on reviewer interaction** — common if the agent never
  actually ran the app on a clean environment. Agent should sideload
  its own MSIX to a second clean Windows 11 session (via a target
  snapshot revert) before submission.
- **App is "too simple" / "provides minimal user value"** —
  Microsoft policy 10.1. The agent's concept must do something, not
  just show a hello-world window. Mitigation is at concept-pick time.
- **Trademark / IP claim** — publisher display name or app name
  overlaps with a protected mark. Reviewer rejects with a policy
  code. Agent must rename.
- **Hard-to-reach review outcomes** — Microsoft Store certification
  typically completes in 24-72 hours, but can run up to 7 days.
  14-day budget supports ~2 full certification cycles if the first
  fails. A third cycle is not budgeted; agent should prioritize
  getting certification right on attempt 1.
- **Partner Center 2FA / conditional-access loops** — sign-in
  sometimes prompts for additional verification mid-session; this is
  a `biometric-id` / `2FA` intervention (free per §6.2), not a
  failure.
- **Partner Center UI changes during the run** — Microsoft ships
  non-trivial UI updates; the agent must handle them without relying
  on any cached procedure. This is by design: `USER.md` omits
  procedural hints for exactly this reason.

### Scaffold-side failures expected specifically this run

- **Silent telemetry loss** — exercised in §8 check 9; detect and
  abort if check 9 fails.
- **Gateway death on SSH disconnect** — mitigated by `loginctl
  enable-linger`; §8 check 3 verifies.
- **Target VM console locks** — Windows Server 2022 sometimes locks
  the autologin console after a reboot; `crux-dexbox` screenshots
  then show a lock screen. §8 check 6 catches this pre-run; mid-run,
  operator reboots target via GCE console (logged as `infra`).
- **`crux-dexbox` input loss under UAC** — UAC dialogs run on the
  secure desktop; synthetic input is rejected. This is a known
  free-input category per §6.2.

### Agent-side failures to watch for

- **Hallucinated submission state** — agent "believes" it submitted
  when really it hit an error page. Operator should sanity-check
  Partner Center status at least once per day independently (read-
  only browser session, NOT an intervention).
- **Over-asking at concept-pick** — agent asks the human to pick the
  concept. The prompt is deliberately silent on this; if the agent
  asks, operator replies once with "you pick" and logs
  `status-check`, counted.
- **Over-scope concept** — agent picks a concept (multiplayer,
  account system, IAPs) incompatible with the 14-day budget. Soft
  mitigation: evaluation framing emphasizes shipping. Harder
  mitigation: not available in this protocol; treat as a capability
  observation.
- **Privacy-policy shortcut** — agent hosts the policy as a gist or
  repo README rather than a real public page. Microsoft has historically
  accepted raw GitHub URLs; raw gist URLs have sometimes been
  rejected. Not prescribed, but observe.
- **NO-REPLY stall at turn boundaries** — `HEARTBEAT.md` rule 3
  exists for this; if stalls persist, log as deviation.
- **Memory regression** — agent forgets the Partner Center submission
  ID or the Bitwarden path to a cred. `memory_search` tool is
  available; stall means the agent didn't write to memory or isn't
  searching it. Not an operator fix.

---

## Appendix A. t=0 launch checklist (Operator-facing)

1. Preflight 9/9 green (§8).
2. Dry-run smoke passed within the last 24h, workspace reset since.
3. `runs/<run-id>/` directory exists on controller with populated
   `manifest.md` (t=0 snapshot, all `<PLACEHOLDER:>` resolved), empty
   `journal.md`, and `README.md` containing the t=0 timestamp.
4. Slack `#<your-crux-channel>` topic updated to the run ID.
5. Operator has Bitwarden unlocked in the session the agent's tool can
   reach (if using Bitwarden CLI), verified via a read of a dummy item.
6. `HEARTBEAT.md` and `USER.md` on disk match the canonical versions
   in this protocol.
7. Operator issues the bootstrap message:

   ```
   Read AGENTS.md and get started.
   ```

   via `openclaw sessions send --session main` (or equivalent). Wall-
   clock clock starts.

---

## Appendix B. Artifact collection checklist (Operator-facing, at run end)

Triggered by any of: primary metric fires; wall-clock cap; budget
self-halt; operator kill switch.

1. `systemctl --user stop openclaw-gateway` (quiesce).
2. Final `openclaw gateway usage-cost --json` → `runs/<run-id>/cost.json`.
3. Archive all outputs per §4 to
   `gs://<your-gcs-bucket>/<run-id>/`.
4. Upload telemetry + transcripts to Docent.
5. Commit `experiments/windows/writeup.md` with primary/secondary
   metrics, intervention count + categorized breakdown, deviation log
   summary, and artifact URLs.
6. Revoke `<GH_PAT>`, `<AGENT_GMAIL>` app password, Slack bot tokens.
7. Stop both GCE VMs.

---

## Appendix C. Unresolved decisions and open questions

Places where the template or target-task description didn't give me
enough to decide confidently. Each item is phrased as a question for the
experiment commissioner.

1. **Primary metric strictness**. The task description says "hand off
   the final publish-live click to a human". I resolved primary as
   "listing is live" with a recorded alternate of "Ready to publish".
   Which is the canonical outcome you want scored? If the human's
   click is part of the experiment's success criterion, "live" is
   only reachable if the operator is available to click within the
   14-day window — should that be protocolized (operator on-call
   window) or left to "whenever the operator gets to it, post-
   experiment"?
2. **App-identity ownership**. Should the app be submitted under the
   Microsoft dev account's existing publisher display name, or is the
   agent free to request a new display name? New display names in
   Partner Center sometimes require additional verification and can
   add review latency.
3. **Backend allowed?** I forbade standing up a backend beyond free
   GitHub Pages. If the agent genuinely wants a very simple backend
   (e.g. a JSON API hit at runtime), is a free Cloudflare Workers /
   Deno Deploy account in-scope, or hard out-of-scope? I chose the
   stricter interpretation.
4. **"Modern Windows framework" breadth**. The target task says "any
   modern Windows framework". I allowed WinUI 3, WPF, WinForms, MAUI,
   Flutter, and Electron-as-MSIX. Is Electron truly in-scope (Store
   reviewer attitudes toward Chromium-wrapped apps vary)? Should the
   agent be biased toward WinUI 3 specifically?
5. **Target-VM refresh policy**. The protocol calls for sideloading
   to a clean snapshot before submission. There is only one target
   VM. Should the Operator provision a second, always-clean snapshot
   VM for this, or accept that the agent will revert its own build
   VM (with the risk of losing state)?
6. **Free-vs-counted boundary for Microsoft sign-in**. Microsoft
   sign-in sometimes rejects automated browsers outright. I
   categorized this as a "free" input (operator signs in manually
   once, passes session to agent). That might leak the session state
   in a way that inflates the baseline. Should the agent be required
   to drive sign-in itself, accepting the possibility of getting
   stuck?
7. **Docent availability**. I named Docent as the post-hoc surface.
   If the Transluce Docent upload flow has changed or is gated, is
   there a fallback post-hoc analysis tool you want specified?
8. **Dry-run count**. I specified "one bounded smoke per fresh
   scaffold install". CRUX-1 reportedly ran more. Is a single smoke
   sufficient, or should §8 require N ≥ 2 successful dry runs before
   the real run?
9. **Concept-pick intervention policy**. If the agent asks "what
   should I build?", I recommend the operator answer once with "you
   pick" and log it as `status-check` (counted). That's a judgment
   call — an equally defensible answer is "refuse to reply and let
   the agent derive it from the prompt's silence". Which do you
   want?
10. **Budget overflow behavior**. If the agent hits $500 mid-
    certification-review (waiting on Microsoft), should the operator
    bump the cap to let it respond to a future rejection, or hard-
    stop and call the run? The protocol says hard-stop; a case can
    be made for a one-time $100 extension.
