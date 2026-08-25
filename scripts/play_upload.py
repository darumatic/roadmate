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

# Release alerts (scripts/notify.py, same directory — both scripts are invoked
# as `python3 scripts/<name>.py`, so it imports cleanly). Guarded because an
# alert must NEVER be the reason a release fails.
try:
    from notify import notify_release
except ImportError:                                    # pragma: no cover
    def notify_release(*_args, **_kwargs):
        return False

SA_KEY = os.path.expanduser("~/.config/roadmate/google-play-service-account.json")
PKG = "com.darumatic.roadmate"
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"
UPLOAD_BASE = (
    "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/"
    f"applications/{PKG}"
)
# Play rejects a release whose notes exceed this, and it rejects it at :commit —
# i.e. *after* the 59 MB bundle has already been uploaded. Check before that.
PLAY_NOTES_MAX = 500
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


def build_track(
    name: str,
    version_code: int,
    notes: str,
    langs: list,
    track: str = "production",
    status: str = "completed",
) -> dict:
    """Track payload: one release on `track` with rollout state `status`.

    `track` is the Play track id — "production", "internal", "alpha" (closed) or
    "beta" (open). Defaults to production so release_android.sh is unaffected.

    `status` is "completed" (full rollout) or "draft" (bundle saved to the track
    but not released). A draft is the only way to *persist* a bundle when Play is
    still blocking the commit — e.g. an undeclared foreground-service permission,
    whose declaration form only appears once Play has seen the uploaded bundle.
    """
    return {
        "track": track,
        "releases": [
            {
                "name": name,
                "versionCodes": [str(version_code)],
                "status": status,
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

    # A non-production track must change ONLY the track id — a testing upload
    # that silently kept status/versionCodes from production would be a
    # production rollout wearing the wrong label.
    internal = build_track("1.2.3 (45)", 45, "notes", ["en-US"], track="internal")
    assert internal["track"] == "internal"
    assert internal["releases"][0]["versionCodes"] == ["45"]
    assert internal["releases"][0]["status"] == "completed"

    # A draft must never roll out to users — it exists only to persist the bundle.
    draft = build_track(
        "1.2.3 (45)", 45, "notes", ["en-US"], track="internal", status="draft"
    )
    assert draft["releases"][0]["status"] == "draft"
    assert draft["track"] == "internal"

    # The real notes file, checked here because release_android.sh runs
    # --self-test before every upload. Play only rejects over-long notes at
    # :commit, after the bundle is uploaded, so catching it here is the
    # difference between a fast failure and a wasted 59 MB round trip.
    with open(DEFAULT_NOTES_FILE) as f:
        real_notes = f.read().strip()
    assert len(real_notes) <= PLAY_NOTES_MAX, (
        f"{DEFAULT_NOTES_FILE} is {len(real_notes)} chars, "
        f"Play's limit is {PLAY_NOTES_MAX}"
    )

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
    p.add_argument(
        "--track",
        default="production",
        choices=["production", "beta", "alpha", "internal"],
        help="Play track to roll out to (default: production)",
    )
    p.add_argument(
        "--draft",
        action="store_true",
        help="save the bundle to the track as a draft instead of rolling it out",
    )
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()

    if args.self_test:
        self_test()
        return
    if not args.aab or not args.name:
        p.error("--aab and --name are required (or use --self-test)")

    with open(args.notes_file) as f:
        notes = f.read().strip()
    if len(notes) > PLAY_NOTES_MAX:
        p.error(
            f"{args.notes_file} is {len(notes)} chars; Play's limit is "
            f"{PLAY_NOTES_MAX}. Shorten it before uploading."
        )

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
            f"/edits/{edit_id}/tracks/{args.track}",
            body=build_track(
                args.name,
                version_code,
                notes,
                langs,
                args.track,
                "draft" if args.draft else "completed",
            ),
        )
        api(token, "POST", f"/edits/{edit_id}:commit")
        if args.draft:
            print(
                f"==> Saved {args.name} as a DRAFT on the {args.track} track "
                "(not released to anyone)."
            )
        else:
            print(
                f"==> Committed {args.name} to the Google Play {args.track} "
                f"track ({langs})."
            )
            print(
                "    NOTE: if the Play Console's Publishing overview shows "
                "'Not yet sent for review'\n"
                "    (managed publishing), a human must click 'Send for "
                "review' there — no API can.\n"
                "    The release only reaches users after that click + Play "
                "review (bit us on 0.1.72)."
            )
            # Committed is NOT live: say so, so the alert can never be read as
            # "users have it" (the 0.1.72 lesson).
            notify_release(
                "Android",
                args.name,
                f"Committed to the Google Play {args.track} track "
                f"({langs}). NOT live yet: Play review must pass, and if "
                "the console shows 'Not yet sent for review' it needs your "
                "click.",
            )
    except Exception:
        api(token, "DELETE", f"/edits/{edit_id}")
        print("edit rolled back after failure", file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
