#!/usr/bin/env python3
"""Upload a signed AAB to Google Play and roll it out to production.

    python3 scripts/play_upload.py --aab build/app/outputs/bundle/release/app-release.aab \
        --name "0.1.40 (40)"

Auth uses the roadmate-play-uploader service account; its JSON key lives at
~/.config/roadmate/google-play-service-account.json (never in the repo).
Release notes are read from store/google_play_release_notes.txt and applied to
every language the listing has. Stdlib + openssl only — no pip dependencies.

--self-test exercises the pure payload/JWT plumbing without touching the
network; release_android.sh runs it before every real upload.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

SA_KEY = os.path.expanduser("~/.config/roadmate/google-play-service-account.json")
PKG = "com.darumatic.roadmate"
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"
UPLOAD_BASE = (
    "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/"
    f"applications/{PKG}"
)
DEFAULT_NOTES_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "store",
    "google_play_release_notes.txt",
)


def b64url(b: bytes) -> bytes:
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def make_jwt(sa: dict, now: int, sign) -> str:
    """Build the RS256 service-account JWT; `sign` maps bytes -> signature bytes."""
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64url(
        json.dumps(
            {
                "iss": sa["client_email"],
                "scope": "https://www.googleapis.com/auth/androidpublisher",
                "aud": "https://oauth2.googleapis.com/token",
                "iat": now,
                "exp": now + 3600,
            }
        ).encode()
    )
    signing_input = header + b"." + claims
    return (signing_input + b"." + b64url(sign(signing_input))).decode()


def openssl_sign(private_key_pem: str, data: bytes) -> bytes:
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
        f.write(private_key_pem)
        keyfile = f.name
    try:
        return subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", keyfile],
            input=data,
            capture_output=True,
            check=True,
        ).stdout
    finally:
        os.remove(keyfile)


def get_token() -> str:
    with open(SA_KEY) as f:
        sa = json.load(f)
    jwt = make_jwt(sa, int(time.time()), lambda d: openssl_sign(sa["private_key"], d))
    data = (
        "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"
        f"&assertion={jwt}"
    ).encode()
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)["access_token"]


def api(token: str, method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            **({"Content-Type": "application/json"} if data else {}),
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read().decode()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} on {method} {path}: {e.read().decode()}", file=sys.stderr)
        raise


def upload_bundle(token: str, edit_id: str, aab_path: str) -> dict:
    with open(aab_path, "rb") as f:
        data = f.read()
    req = urllib.request.Request(
        f"{UPLOAD_BASE}/edits/{edit_id}/bundles?uploadType=media",
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/octet-stream",
        },
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def build_track(name: str, version_code: int, notes: str, langs: list) -> dict:
    """Production-track payload: full rollout of one release."""
    return {
        "track": "production",
        "releases": [
            {
                "name": name,
                "versionCodes": [str(version_code)],
                "status": "completed",
                "releaseNotes": [
                    {"language": lang, "text": notes} for lang in langs
                ],
            }
        ],
    }


def self_test() -> None:
    track = build_track("1.2.3 (45)", 45, "notes", ["en-US", "en-AU"])
    assert track["track"] == "production"
    release = track["releases"][0]
    assert release["versionCodes"] == ["45"]
    assert release["status"] == "completed"
    assert [n["language"] for n in release["releaseNotes"]] == ["en-US", "en-AU"]

    sa = {"client_email": "x@y.iam.gserviceaccount.com"}
    jwt = make_jwt(sa, 1_700_000_000, lambda d: b"sig")
    header, claims, sig = jwt.split(".")
    decoded = json.loads(base64.urlsafe_b64decode(claims + "=="))
    assert decoded["iss"] == sa["client_email"]
    assert decoded["exp"] - decoded["iat"] == 3600
    assert base64.urlsafe_b64decode(sig + "==") == b"sig"
    print("self-test OK")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--aab", help="path to the signed .aab")
    p.add_argument("--name", help='release name, e.g. "0.1.40 (40)"')
    p.add_argument("--notes-file", default=DEFAULT_NOTES_FILE)
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()

    if args.self_test:
        self_test()
        return
    if not args.aab or not args.name:
        p.error("--aab and --name are required (or use --self-test)")

    with open(args.notes_file) as f:
        notes = f.read().strip()

    token = get_token()
    edit_id = api(token, "POST", "/edits")["id"]
    try:
        listings = api(token, "GET", f"/edits/{edit_id}/listings")
        langs = [l["language"] for l in listings.get("listings", [])] or ["en-US"]

        print(f"==> Uploading {args.aab} ({os.path.getsize(args.aab)} bytes)")
        version_code = upload_bundle(token, edit_id, args.aab)["versionCode"]
        print(f"    versionCode {version_code}")

        api(
            token,
            "PUT",
            f"/edits/{edit_id}/tracks/production",
            body=build_track(args.name, version_code, notes, langs),
        )
        api(token, "POST", f"/edits/{edit_id}:commit")
        print(f"==> Released {args.name} to Google Play production ({langs}).")
    except Exception:
        api(token, "DELETE", f"/edits/{edit_id}")
        print("edit rolled back after failure", file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
