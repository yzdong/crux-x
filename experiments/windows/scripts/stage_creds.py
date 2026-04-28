#!/usr/bin/env python3
"""Stage CRUX-Windows credentials from GCP Secret Manager into a JSON file.

Pulls a fixed set of secrets from `projects/<your-gcp-project>/secrets/*` (version
`latest`) and writes them as a single JSON object to `~/.dexbox/shared/creds.json`
(mode 0600), which the agent harness reads at startup.

Workarounds / quirks:
  * `dexbox start` creates `~/.dexbox/shared/` owned by root:root. We chown it
    back to the invoking user first (idempotent — skip sudo if already owned).
  * Missing secrets are written as the sentinel string "__MISSING__" and a WARN
    line is printed to stderr; the script does NOT abort.

Prefers the `google-cloud-secret-manager` SDK. Falls back to shelling out to
`gcloud secrets versions access` if the SDK import fails, so the script still
works on a minimal VM.

Usage:
    ./stage_creds.py              # fetch + write
    ./stage_creds.py --dry-run    # list what would be fetched, don't call GCP
"""

from __future__ import annotations

import argparse
import json
import os
import pwd
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from typing import Callable

PROJECT_ID = "<your-gcp-project>"
MISSING_SENTINEL = "__MISSING__"
OUTPUT_PATH = Path.home() / ".dexbox" / "shared" / "creds.json"

# JSON key -> Secret Manager secret name. Edit this dict to add/rename.
SECRETS: dict[str, str] = {
    "microsoft_email": "microsoft-email",
    "microsoft_password": "microsoft-password",
    "partner_center_login": "partner-center-login",
    "partner_center_password": "partner-center-password",
    "github_email": "github-email",
    "github_pat": "github-pat",
    "gmail_email": "gmail-email",
    "gmail_app_password": "gmail-app-password",
    "slack_webhook_url": "slack-crux-windows",
    "anthropic_api_key": "anthropic-api-key",
    "support_phone": "support-phone",
    "support_email": "support-email",
    "windows_admin_password": "windows-admin-password",
}


def warn(msg: str) -> None:
    print(f"WARN: {msg}", file=sys.stderr)


def die(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def fix_shared_dir_ownership(shared_dir: Path) -> None:
    """Chown `shared_dir` back to the invoking user if it's owned by root.

    Known bug: `dexbox start` creates `~/.dexbox/shared/` as root:root, which
    makes subsequent writes fail with Permission denied. Idempotent — no-op if
    the directory is already user-owned or doesn't exist yet.
    """
    if not shared_dir.exists():
        shared_dir.parent.mkdir(parents=True, exist_ok=True)
        return
    st = shared_dir.stat()
    user = pwd.getpwuid(os.getuid()).pw_name
    if st.st_uid == os.getuid():
        return  # already user-owned; nothing to do
    print(f"INFO: {shared_dir} is owned by uid={st.st_uid}, chowning to {user}", file=sys.stderr)
    try:
        subprocess.run(
            ["sudo", "chown", "-R", f"{user}:{user}", str(shared_dir)],
            check=True,
        )
    except subprocess.CalledProcessError as e:
        die(f"sudo chown failed on {shared_dir}: {e}")
    except FileNotFoundError:
        die("sudo not found; cannot fix ownership of ~/.dexbox/shared/")


def build_sdk_fetcher(project_id: str) -> Callable[[str], str | None] | None:
    """Return an SDK-backed fetcher, or None if the SDK isn't importable or ADC is unset."""
    try:
        from google.api_core import exceptions as gax_exceptions  # type: ignore
        from google.auth import exceptions as auth_exceptions  # type: ignore
        from google.cloud import secretmanager  # type: ignore
    except ImportError:
        return None

    try:
        client = secretmanager.SecretManagerServiceClient()
    except auth_exceptions.DefaultCredentialsError as e:
        warn(f"SDK available but Application Default Credentials not set: {e}")
        return None

    def fetch(secret_name: str) -> str | None:
        name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
        try:
            resp = client.access_secret_version(request={"name": name})
        except gax_exceptions.NotFound:
            return None
        except gax_exceptions.PermissionDenied as e:
            warn(f"permission denied for {secret_name}: {e}")
            return None
        return resp.payload.data.decode("utf-8")

    return fetch


def build_gcloud_fetcher(project_id: str) -> Callable[[str], str | None]:
    """Fallback fetcher using `gcloud secrets versions access`."""
    if not shutil.which("gcloud"):
        die("gcloud CLI not found and google-cloud-secret-manager not importable")

    # Cheap auth check: a failed ADT here will surface as an auth error later,
    # but we can sanity-check that SOME account is active.
    result = subprocess.run(
        ["gcloud", "auth", "list", "--filter=status:ACTIVE", "--format=value(account)"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        die("gcloud is not authenticated. Run: gcloud auth login  (and: gcloud auth application-default login)")

    def fetch(secret_name: str) -> str | None:
        proc = subprocess.run(
            [
                "gcloud", "secrets", "versions", "access", "latest",
                f"--secret={secret_name}",
                f"--project={project_id}",
            ],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            stderr = proc.stderr.lower()
            if "not found" in stderr or "notfound" in stderr:
                return None
            warn(f"gcloud access failed for {secret_name}: {proc.stderr.strip()}")
            return None
        return proc.stdout

    return fetch


def write_creds(creds: dict[str, str], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(creds, indent=2, sort_keys=True) + "\n")
    tmp.chmod(stat.S_IRUSR | stat.S_IWUSR)  # 0600
    tmp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="List what would be fetched and exit; don't hit Secret Manager or write files.")
    args = parser.parse_args()

    if args.dry_run:
        print(f"DRY RUN — would fetch {len(SECRETS)} secrets from project {PROJECT_ID}:")
        for json_key, secret_name in SECRETS.items():
            print(f"  {json_key:<28} <- projects/{PROJECT_ID}/secrets/{secret_name}")
        print(f"Would write: {OUTPUT_PATH} (mode 0600)")
        return 0

    fix_shared_dir_ownership(OUTPUT_PATH.parent)

    fetcher = build_sdk_fetcher(PROJECT_ID)
    if fetcher is None:
        warn("google-cloud-secret-manager SDK not installed; falling back to gcloud CLI")
        fetcher = build_gcloud_fetcher(PROJECT_ID)

    creds: dict[str, str] = {}
    missing: list[str] = []
    for json_key, secret_name in SECRETS.items():
        value = fetcher(secret_name)
        if value is None:
            warn(f"secret {secret_name!r} not found; writing {MISSING_SENTINEL}")
            creds[json_key] = MISSING_SENTINEL
            missing.append(json_key)
        else:
            creds[json_key] = value.rstrip("\n")

    write_creds(creds, OUTPUT_PATH)

    present = [k for k in creds if creds[k] != MISSING_SENTINEL]
    print(f"Wrote {OUTPUT_PATH} (mode 0600)")
    print(f"  present ({len(present)}): {', '.join(sorted(present)) or '(none)'}")
    print(f"  missing ({len(missing)}): {', '.join(sorted(missing)) or '(none)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
