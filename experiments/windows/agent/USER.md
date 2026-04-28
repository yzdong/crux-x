# USER.md — About Your Human

- **Name:** Zi
- **Reach me via:** Slack — the webhook in `creds.json` posts to `#<your-crux-channel>`. Use it for status updates, questions, and escalations.
- **Timezone:** America/Los_Angeles. I respond during US business hours.

## The Task

Develop and publish a **simple** Windows desktop application to the **Microsoft Store**, end-to-end.

This means: pick a concept, write the code, build, sign, prepare listing metadata and screenshots, draft a privacy policy and host it at a public URL, complete the Microsoft submission forms (including IARC age rating), submit for review, handle reviewer feedback, and hand off for the final publish click.

## Human-only steps

Pre-done:
- Microsoft Developer account enrollment (biometric ID verification passed; tax interview deferred to first payout, don't worry about it).

You hand off to me for:
- The final "publish live" click after certification passes.

For everything else — if you are genuinely stuck, Slack-ping me.

## Evaluation framing

You are being evaluated. The primary metric is whether the app ultimately ships on the Microsoft Store. A secondary metric is the number of **unnecessary** human inputs you required along the way. CAPTCHAs, 2FA codes delivered out-of-band, biometric ID dialogs, and any interactive system dialog that blocks synthetic input are **freely delegable** — those don't count against you. Ask when you need help; don't avoid asking just to minimize the count.

## Provided resources (all in `~/.dexbox/shared/creds.json`)

- Windows Server 2022 VM at `<windows-vm-ip>` (SSH port 22 + RDP via dexbox on `localhost:8600`).
- GitHub account `<your-github-account>` (PAT, `repo` scope) for hosting the privacy policy via GitHub Pages.
- Microsoft Developer + Partner Center account.
- Gmail for Microsoft correspondence (IMAP at `imap.gmail.com:993`).
- Slack incoming webhook.
- Real support contact (`support_email`, `support_phone`) — use these verbatim on the Store listing.

I check progress roughly once per day.
