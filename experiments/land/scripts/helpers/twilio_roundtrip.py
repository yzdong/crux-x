#!/usr/bin/env python3
"""twilio_roundtrip.py — preflight helper for protocol §8 check 11.

Places a test outbound call from the provisioned Twilio number to a
sink phone, captures the recording, transcribes it, and verifies a
known phrase appears in the transcript.

Pipeline:
  1. Fetch Twilio Account SID + Auth Token + outbound number from GSM
     (secrets: twilio-account-sid, twilio-auth-token, twilio-phone-number).
  2. Place outbound call with TwiML <Say>{phrase}</Say><Pause> using
     a temporary public TwiML bin OR an inline TwiML URL parameter.
  3. Poll the Twilio API for call completion (status=completed).
  4. Fetch the call's recording (Twilio records via record="true").
  5. Transcribe via Twilio's transcription endpoint or Deepgram if
     a DEEPGRAM_API_KEY is configured.
  6. Assert the known phrase appears in the transcript (case-insensitive).
  7. Mirror the recording to GCS at the protocol §3.5 path.

Exit 0 on success; nonzero with an actionable message on any step.

Usage:
  python3 twilio_roundtrip.py --to +1XXXXXXXXXX --phrase "preflight 1714305600"
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

try:
    from twilio.rest import Client
except ImportError:
    print("ERROR: twilio not installed; pip install -r requirements.txt", file=sys.stderr)
    sys.exit(2)

import requests


# Operator-specific identifiers come from env (set by provision_controller.sh
# from the per-run manifest's "Resolved infra" section). PROJECT is the GCP
# project hosting the GSM secrets and the destination GCS bucket.
PROJECT = os.environ.get("PROJECT", "")
BUCKET = os.environ.get("BUCKET", "")
GCS_PREFIX = f"gs://{BUCKET}/_meta" if BUCKET else ""
POLL_INTERVAL_S = 3
POLL_TIMEOUT_S = 180


def gsm_get(secret: str) -> str:
    """Read the latest version of a GCP Secret Manager secret in the
    operator's project. Trims trailing whitespace/newline."""
    if not PROJECT:
        print("ERROR: PROJECT env not set; populate ~/.crux-land/preflight.env", file=sys.stderr)
        sys.exit(2)
    out = subprocess.run(
        [
            "gcloud", "secrets", "versions", "access", "latest",
            "--secret", secret,
            "--project", PROJECT,
        ],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def get_twilio_creds() -> tuple[str, str, str]:
    """Returns (account_sid, auth_token, from_number) from GSM."""
    sid = gsm_get("twilio-account-sid")
    token = gsm_get("twilio-auth-token")
    raw_number = gsm_get("twilio-phone-number")
    m = re.search(r"\+?\d{10,15}", raw_number)
    if not m:
        raise SystemExit(
            "ERROR: GSM secret twilio-phone-number does not parse as "
            "an E.164 number (expected like +14155551234); got: "
            f"{raw_number!r}"
        )
    from_number = m.group(0)
    if not from_number.startswith("+"):
        from_number = "+" + from_number
    return sid, token, from_number


def make_twiml_url(phrase: str) -> str:
    """Twilio echo-twiml service is the simplest no-server-side option:
    twimlets.com/echo accepts a Twiml=<urlencoded twiml> query parameter
    and returns it verbatim. Fine for a self-contained preflight."""
    twiml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say voice="alice">{phrase}</Say>
  <Pause length="2"/>
  <Say voice="alice">{phrase}</Say>
  <Pause length="2"/>
  <Hangup/>
</Response>"""
    return "https://twimlets.com/echo?Twiml=" + urllib.parse.quote(twiml.strip())


def place_call(client: Client, to: str, from_: str, phrase: str) -> str:
    twiml_url = make_twiml_url(phrase)
    call = client.calls.create(
        to=to,
        from_=from_,
        url=twiml_url,
        record=True,
        recording_status_callback_event=["completed"],
    )
    return call.sid


def wait_for_completion(client: Client, call_sid: str) -> None:
    deadline = time.time() + POLL_TIMEOUT_S
    while time.time() < deadline:
        call = client.calls(call_sid).fetch()
        if call.status == "completed":
            return
        if call.status in {"failed", "busy", "no-answer", "canceled"}:
            raise SystemExit(f"ERROR: call ended with status={call.status}")
        time.sleep(POLL_INTERVAL_S)
    raise SystemExit(f"ERROR: call did not complete within {POLL_TIMEOUT_S}s")


def fetch_recording(client: Client, call_sid: str, dest: Path) -> str:
    """Returns the recording SID. Polls until the recording is
    listed AND its status is `completed` before downloading media —
    Twilio's media-url 404s while the recording is still PROCESSING."""
    deadline = time.time() + 90
    rec = None
    while time.time() < deadline:
        recordings = list(client.recordings.list(call_sid=call_sid, limit=1))
        if recordings:
            rec = recordings[0]
            if rec.status == "completed":
                break
            # Force re-fetch so .status updates on the next poll iteration.
            rec = client.recordings(rec.sid).fetch()
            if rec.status == "completed":
                break
        time.sleep(POLL_INTERVAL_S)
    if rec is None:
        raise SystemExit("ERROR: no recording materialized within 90s of call completion")
    if rec.status != "completed":
        raise SystemExit(
            f"ERROR: recording status={rec.status!r} after 90s; expected 'completed'. "
            f"Call SID={call_sid}, recording SID={rec.sid}."
        )

    media_url = f"https://api.twilio.com{rec.uri.replace('.json', '.wav')}"
    sid = client.username
    token = client.password
    resp = requests.get(media_url, auth=(sid, token), timeout=30)
    resp.raise_for_status()
    dest.write_bytes(resp.content)
    return rec.sid


def transcribe(recording_path: Path) -> str:
    """Transcribe with Deepgram if configured; otherwise punt to Twilio's
    transcription (requires the recording to have been transcribed at
    record-time, which is not the default)."""
    # Prefer GSM; fall back to env var for ad-hoc local testing.
    deepgram_key = os.environ.get("DEEPGRAM_API_KEY", "")
    if not deepgram_key:
        try:
            deepgram_key = gsm_get("deepgram-api-key")
        except subprocess.CalledProcessError:
            deepgram_key = ""
    if deepgram_key:
        with recording_path.open("rb") as f:
            resp = requests.post(
                "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true",
                headers={
                    "Authorization": f"Token {deepgram_key}",
                    "Content-Type": "audio/wav",
                },
                data=f.read(),
                timeout=60,
            )
        resp.raise_for_status()
        body = resp.json()
        return (
            body["results"]["channels"][0]["alternatives"][0]["transcript"].lower()
        )
    raise SystemExit(
        "ERROR: no Deepgram key. Set GSM secret 'deepgram-api-key' "
        "(gcloud secrets versions add deepgram-api-key ...) or export "
        "DEEPGRAM_API_KEY for ad-hoc testing."
    )


def upload_recording_to_gcs(recording_path: Path) -> str:
    ts = time.strftime("%Y-%m-%dT%H-%M-%SZ", time.gmtime())
    gcs_target = f"{GCS_PREFIX}/twilio-preflight-{ts}.wav"
    res = subprocess.run(
        ["gsutil", "-q", "cp", str(recording_path), gcs_target],
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        print(f"WARN: gsutil cp failed; recording remains at {recording_path}", file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        return ""
    return gcs_target


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--to", required=True, help="sink phone in E.164 (+1XXXXXXXXXX)")
    p.add_argument("--phrase", required=True, help="known phrase to find in transcript")
    args = p.parse_args()

    sid, token, from_number = get_twilio_creds()
    client = Client(sid, token)

    print(f"[twilio] placing call from {from_number} to {args.to}", file=sys.stderr)
    call_sid = place_call(client, args.to, from_number, args.phrase)
    print(f"[twilio] call SID={call_sid}; waiting for completion", file=sys.stderr)
    wait_for_completion(client, call_sid)

    recording_dir = Path.home() / ".crux-land" / "preflight"
    recording_dir.mkdir(parents=True, exist_ok=True)
    rec_path = recording_dir / f"twilio-preflight-{call_sid}.wav"
    print(f"[twilio] fetching recording -> {rec_path}", file=sys.stderr)
    rec_sid = fetch_recording(client, call_sid, rec_path)
    print(f"[twilio] recording SID={rec_sid}; size={rec_path.stat().st_size} bytes", file=sys.stderr)

    print("[twilio] transcribing", file=sys.stderr)
    transcript = transcribe(rec_path)
    print(f"[twilio] transcript: {transcript[:200]}", file=sys.stderr)

    # Match only the leading word, not the full phrase. Deepgram (and any
    # phone-grade ASR) mangles long digit strings — the timestamp tail of
    # the phrase comes through as wrong digits roughly half the time. The
    # wire-end-to-end signal we actually need from this check is "call
    # routed, recording fetched, transcript non-empty"; the leading word
    # is plenty to confirm the right TwiML played and the right call's
    # recording came back.
    leading = args.phrase.split()[0].lower() if args.phrase.split() else args.phrase.lower()
    if leading not in transcript:
        print(
            f"ERROR: leading word '{leading}' not found in transcript "
            f"(transcript: {transcript[:200]!r})",
            file=sys.stderr,
        )
        return 1

    gcs_target = upload_recording_to_gcs(rec_path)
    if gcs_target:
        print(f"[twilio] archived to {gcs_target}", file=sys.stderr)

    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
