# CRUX-Land — Operator (you) provisioning checklist

Things only you can do — account signups, ID-bearing KYC, payment-
bearing actions, identity-attached items. Everything in this file is
external to the controller VM and must be done before the controller
preflight can reach 10/10 green.

**Source of truth for every credential is GCP Secret Manager**
(project `${PROJECT}` — your own GCP project; export `PROJECT=<your-project-id>`
once before running the helpers below). The controller VM reads via
`gcloud secrets versions access latest --secret=<name>` thanks to
its cloud-platform service-account scope + the
`roles/secretmanager.secretAccessor` IAM binding. There is **no
Bitwarden** in this experiment.

Helper one-liner to populate a secret from your laptop:

```sh
# Create + set in one shot. Re-run safely with --force on add.
secret_set() {
  local name=$1 value=$2
  gcloud secrets create "$name" --project=${PROJECT} \
    --replication-policy=automatic 2>/dev/null || true
  printf %s "$value" | gcloud secrets versions add "$name" \
    --project=${PROJECT} --data-file=-
}
```

Order: top to bottom.

---

## 1. GCS bucket creation (after `gcloud auth login`)

```sh
gcloud auth login
export PROJECT=<your-gcp-project-id>           # also record in manifest:infra.gcp_project
export BUCKET=<your-bucket-name>               # also record in manifest:infra.gcs_bucket_uri
gcloud storage buckets create gs://${BUCKET} \
  --project=${PROJECT} \
  --location=<your-gcp-region> \
  --default-storage-class=STANDARD \
  --uniform-bucket-level-access \
  --retention-period=30d
```

## 2. Slack channel + bot

- Create `#crux-land` (private, just you + the bot).
- Reuse the existing `crux-windows-bot` Slack app — invite it to
  `#crux-land`. No new app needed.
- **Required Bot Token Scopes** (verify at
  `api.slack.com/apps/<APP_ID>/oauth` → "Bot Token Scopes"; if any
  are missing, add them and click "Reinstall to Workspace" to
  regenerate the bot token):
  - `chat:write` — post status messages
  - `chat:write.public` — post in channels the bot isn't a member of
  - `app_mentions:read` — read @-mentions
  - `reactions:write` — emoji reactions
  - `channels:history` — read message history (needed for inbound
    Socket Mode messages)
  - `channels:read`, `groups:read`, `im:read`, `mpim:read` —
    enumerate channels via `users.conversations` (needed by some
    preflight + agent paths)
- No custom slash-command behavior. Preflight check 7 validates the
  bot by posting a real "preflight ok" message via `chat.postMessage`
  to `#crux-land` — proves write capability + channel membership +
  scope correctness in one shot. Watch for the message in the
  channel after preflight passes.

**GSM secrets** (the canonical source; values originate here, get
mirrored into `~/.openclaw/openclaw.json` `channels.slack.*` at
provision time so the OpenClaw runtime can consume them):

```sh
secret_set slack-bot-token   "xoxb-..."
secret_set slack-app-token   "xapp-1-..."
```

Tokens are already copied into `crux-land-ctrl:~/.openclaw/openclaw.json`
from the CRUX-Windows controller. Push them into GSM as well so the
config is reproducible from secrets alone.

## 3. Dedicated Gmail

Provision a Gmail or Google Workspace user that will be the agent's
correspondence address (will appear as the sender on outbound seller
inquiries / title-co correspondence). Generate an IMAP+SMTP app
password (Account → Security → App passwords); 2FA must be on.

**GSM secrets**:

```sh
secret_set gmail-email        "<gmail-address>"
secret_set gmail-app-password "<app-password>"
```

## 4. Twilio

Sign up at `twilio.com` (use the dedicated Gmail above as the account
email). Set a strong password + record a recovery code; store both:

```sh
secret_set twilio-password       "<password>"
secret_set twilio-recovery-code  "<recovery-code>"
```

Then:

```sh
gcloud secrets versions access latest --secret=twilio-password         --project=${PROJECT}
gcloud secrets versions access latest --secret=twilio-recovery-code   --project=${PROJECT}
```

1. Sign in at `login.twilio.com`.
2. Add ~$30 of credit (Console → Account → Billing → Add Funds).
3. Buy one US local Voice number (Console → Phone Numbers → Buy).
4. Confirm outbound calling to all 50 US states is enabled.
5. Copy three values from the Console root and store them:

```sh
secret_set twilio-account-sid    "AC..."
secret_set twilio-auth-token     "..."
secret_set twilio-phone-number   "+1XXXXXXXXXX"
```

## 5. Deepgram (transcription)

Sign up at `deepgram.com`. Free tier gives $200 of credit which is
ample. Generate a project-scoped API key.

```sh
secret_set deepgram-api-key "<key>"
```

## 6. Sink phone + sink email (your own)

Pick two endpoints **you control** for the preflight tests. **Don't
write the values into this file or any committed file** — they're
PII; they live in GSM only.

- **Sink phone**: any phone you can answer for ~10s during preflight
  check 9 (Twilio voice). E.164 format (e.g., `+1XXXXXXXXXX`).
- **Sink email**: any mailbox you control + can hand-reply from
  during dry-run smoke 2 (~60s window). Auto-reply infra is optional.

```sh
secret_set crux-land-sink-phone "+1XXXXXXXXXX"
secret_set crux-land-sink-email "<your-email>"
```

The controller reads these from GSM (preflight.sh's check 9 calls
`gcloud secrets versions access latest --secret=crux-land-sink-phone
--project=${PROJECT}` directly).

## 7. Personal bank wire enablement (deferred)

**Status**: deferred until closer to closing. Only blocks at the
wire-authorization step (typically day 7–14 of the run, after title
commitment is clean). Doesn't block preflight, dry runs, or the
search/offer/escrow phases.

Some banks gate outbound wires behind a one-time phone enablement.
Call yours and:
- Confirm outbound wires are enabled on your account.
- Confirm daily wire cap ≥ $2,000.
- Get the wire-execution UX squared away (some banks require an
  auth-app code at execution time; pre-test with a $1 wire to a
  trusted account if you've never wired before).

No GSM secret — **never put bank credentials in any system the agent
can read**.

## 8. After all of the above

1. SSH to the controller: `gcloud compute ssh ${CONTROLLER_VM:-crux-land-ctrl} --tunnel-through-iap --zone=${ZONE:-us-central1-a}`
2. Verify GSM access: `gcloud secrets versions access latest --secret=gmail-email --project=${PROJECT}` should print the email.
3. Verify each newly-created secret is reachable from the VM the
   same way.
4. Verify `channels.slack.{botToken,appToken}` are set in
   `~/.openclaw/openclaw.json` per §2 above.
5. Edit `~/.crux-land/preflight.env` with values from the
   `crux-land-sink-phone` / `crux-land-sink-email`
   secrets (or have provision_controller.sh's last step do it for you).
6. `bash ~/crux-land/experiments/land/scripts/preflight.sh --verbose`
7. Iterate until 10/10 green.

Then we proceed to dry-run smoke 1 + 2, then kickoff.
