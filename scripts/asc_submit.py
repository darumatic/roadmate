#!/usr/bin/env python3
"""Finish an iOS release in App Store Connect after the IPA upload.

    python3 scripts/asc_submit.py --version 0.1.40 --build 40

Waits for the uploaded build to finish Apple-side processing, sets the
"What's New" text (from store/apple_whats_new.txt) on the editable app
version, renames it to --version, attaches the build, and submits (or
resubmits) for review — the steps that used to be manual in the ASC website.

Auth: App Store Connect API key. Key id / issuer come from ASC_KEY_ID /
ASC_ISSUER_ID (same env vars release_ios.sh uses for the upload) with the
.p8 file in ~/.appstoreconnect/private_keys/. Stdlib + openssl only.

Guard rail: the What's New text is refused if it mentions other stores or
platforms — Apple rejected 0.1.38 under guideline 2.3.10 for a Google Play
reference in exactly this field.

--dry-run performs only read calls and prints what would happen.
--self-test exercises the pure helpers offline; release_ios.sh runs it
before every real submission.
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

APP_ID = "6788635496"  # RoadMate AU
KEY_ID = os.environ.get("ASC_KEY_ID", "PVV887QV57")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "1623d92a-9373-42ee-8bca-9435f6df7f4d")
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
BASE = "https://api.appstoreconnect.apple.com"
DEFAULT_NOTES_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "store",
    "apple_whats_new.txt",
)

# Guideline 2.3.10: App Store metadata must not reference third-party
# stores/platforms (0.1.38 rejection).
FORBIDDEN_IN_WHATS_NEW = ("google play", "play store", "android")

EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}


def whats_new_violations(text: str) -> list:
    low = text.lower()
    return [w for w in FORBIDDEN_IN_WHATS_NEW if w in low]


def _b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _der_to_raw(der: bytes) -> bytes:
    """Convert an openssl DER ECDSA signature to raw r||s (64 bytes)."""
    assert der[0] == 0x30
    i = 2
    if der[1] & 0x80:
        i += der[1] & 0x7F
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        ln = der[i + 1]
        val = der[i + 2 : i + 2 + ln]
        out += val.lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + ln
    return out


def jwt_parts(now: int, key_id: str, issuer_id: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1200,
               "aud": "appstoreconnect-v1"}
    return (_b64url(json.dumps(header).encode()) + "."
            + _b64url(json.dumps(payload).encode()))


_token_cache = {"tok": None, "exp": 0}


def token() -> str:
    now = int(time.time())
    if _token_cache["tok"] and now < _token_cache["exp"] - 60:
        return _token_cache["tok"]
    signing_input = jwt_parts(now, KEY_ID, ISSUER_ID)
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        f.write(signing_input.encode())
        msg_path = f.name
    try:
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", KEY_PATH, msg_path],
            capture_output=True, check=True).stdout
    finally:
        os.unlink(msg_path)
    tok = signing_input + "." + _b64url(_der_to_raw(der))
    _token_cache.update(tok=tok, exp=now + 1200)
    return tok


def request(method: str, path: str, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode(errors="replace")


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def expect(status: int, out, what: str):
    if status >= 300:
        die(f"{what} failed (HTTP {status}): {json.dumps(out)[:800]}")
    return out


def wait_for_build(build_no: str, timeout_s: int, poll_s: int = 120) -> str:
    """Poll until the uploaded build leaves PROCESSING; return its ASC id."""
    deadline = time.time() + timeout_s
    while True:
        status, out = request(
            "GET",
            f"/v1/builds?filter[app]={APP_ID}&filter[version]={build_no}"
            "&sort=-uploadedDate&limit=1",
        )
        expect(status, out, "listing builds")
        builds = out.get("data", [])
        state = builds[0]["attributes"]["processingState"] if builds else None
        if state == "VALID":
            print(f"    build {build_no} processed (id {builds[0]['id']})")
            return builds[0]["id"]
        if state in ("FAILED", "INVALID"):
            die(f"build {build_no} processing ended in {state}")
        if time.time() > deadline:
            die(f"build {build_no} still {state or 'absent'} after {timeout_s}s")
        print(f"    build {build_no}: {state or 'not visible yet'} — waiting…")
        time.sleep(poll_s)


def find_or_create_version(version: str, dry_run: bool) -> tuple:
    status, out = request(
        "GET", f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=5"
    )
    expect(status, out, "listing app versions")
    for v in out.get("data", []):
        state = v["attributes"]["appStoreState"]
        if state in EDITABLE_STATES:
            print(f"    editable version {v['attributes']['versionString']}"
                  f" ({state}, id {v['id']})")
            return v["id"], v["attributes"]["versionString"]
        if state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            die(f"version {v['attributes']['versionString']} is {state} — "
                "nothing to do (cancel it in ASC first if you meant to replace it)")
    if dry_run:
        print(f"    would create version {version}")
        return None, None
    status, out = request("POST", "/v1/appStoreVersions", body={
        "data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }
    })
    expect(status, out, "creating app version")
    print(f"    created version {version} (id {out['data']['id']})")
    return out["data"]["id"], version


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--version", help="marketing version, e.g. 0.1.40")
    p.add_argument("--build", help="build number, e.g. 40")
    p.add_argument("--notes-file", default=DEFAULT_NOTES_FILE)
    p.add_argument("--wait-timeout", type=int, default=5400,
                   help="max seconds to wait for build processing")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()

    if args.self_test:
        self_test()
        return
    if not args.version or not args.build:
        p.error("--version and --build are required (or use --self-test)")

    with open(args.notes_file) as f:
        notes = f.read().strip()
    bad = whats_new_violations(notes)
    if bad:
        die(f"What's New text mentions {bad} — Apple rejects this "
            f"(guideline 2.3.10). Edit {args.notes_file}.")

    print("==> Waiting for build processing")
    if args.dry_run:
        status, out = request(
            "GET",
            f"/v1/builds?filter[app]={APP_ID}&filter[version]={args.build}"
            "&sort=-uploadedDate&limit=1",
        )
        expect(status, out, "listing builds")
        data = out.get("data", [])
        state = data[0]["attributes"]["processingState"] if data else "absent"
        build_id = data[0]["id"] if data else None
        print(f"    build {args.build}: {state}")
    else:
        build_id = wait_for_build(args.build, args.wait_timeout)

    print("==> App version")
    version_id, current_string = find_or_create_version(args.version, args.dry_run)
    if version_id is None:  # dry-run would-create path
        print("    (dry run: stopping before writes)")
        return

    if args.dry_run:
        print(f"    would: rename to {args.version} (now {current_string}), "
              f"set What's New, attach build {args.build}, submit for review")
        return

    if current_string != args.version:
        status, out = request("PATCH", f"/v1/appStoreVersions/{version_id}", body={
            "data": {"type": "appStoreVersions", "id": version_id,
                     "attributes": {"versionString": args.version}}
        })
        expect(status, out, "renaming version")
        print(f"    renamed {current_string} -> {args.version}")

    print("==> What's New")
    status, out = request(
        "GET",
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
    )
    expect(status, out, "listing localizations")
    for loc in out.get("data", []):
        status, patched = request(
            "PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", body={
                "data": {"type": "appStoreVersionLocalizations",
                         "id": loc["id"],
                         "attributes": {"whatsNew": notes}}
            })
        expect(status, patched, f"setting whatsNew ({loc['attributes']['locale']})")
        print(f"    whatsNew set for {loc['attributes']['locale']}")

    print("==> Attach build")
    status, out = request(
        "PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
        body={"data": {"type": "builds", "id": build_id}})
    expect(status, out, "attaching build")
    print(f"    build {args.build} attached")

    print("==> Submit for review")
    status, out = request(
        "GET",
        f"/v1/reviewSubmissions?filter[app]={APP_ID}"
        "&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES&limit=1",
    )
    expect(status, out, "listing review submissions")
    subs = out.get("data", [])
    if subs:
        sub_id = subs[0]["id"]
        print(f"    reusing open submission {sub_id} "
              f"({subs[0]['attributes']['state']})")
    else:
        status, out = request("POST", "/v1/reviewSubmissions", body={
            "data": {"type": "reviewSubmissions",
                     "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {"type": "apps",
                                                        "id": APP_ID}}}}})
        expect(status, out, "creating review submission")
        sub_id = out["data"]["id"]
        print(f"    created submission {sub_id}")

    status, out = request(
        "GET", f"/v1/reviewSubmissions/{sub_id}/items")
    expect(status, out, "listing submission items")
    if not out.get("data"):
        status, out = request("POST", "/v1/reviewSubmissionItems", body={
            "data": {"type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions",
                                              "id": sub_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions",
                                             "id": version_id}}}}})
        expect(status, out, "adding version to submission")
        print("    version added to submission")

    status, out = request("PATCH", f"/v1/reviewSubmissions/{sub_id}", body={
        "data": {"type": "reviewSubmissions", "id": sub_id,
                 "attributes": {"submitted": True}}})
    expect(status, out, "submitting for review")
    print(f"==> Submitted {args.version} ({args.build}) for App Review.")


def self_test() -> None:
    assert whats_new_violations("Bug fixes and improvements") == []
    assert whats_new_violations("now on Google Play!") == ["google play"]
    assert whats_new_violations("Web, App Store and Play Store links") == \
        ["play store"]

    parts = jwt_parts(1_700_000_000, "KEYID", "issuer-uuid")
    header_b64, claims_b64 = parts.split(".")
    pad = lambda s: s + "=" * (-len(s) % 4)  # noqa: E731
    header = json.loads(base64.urlsafe_b64decode(pad(header_b64)))
    claims = json.loads(base64.urlsafe_b64decode(pad(claims_b64)))
    assert header == {"alg": "ES256", "kid": "KEYID", "typ": "JWT"}
    assert claims["aud"] == "appstoreconnect-v1"
    assert claims["exp"] - claims["iat"] == 1200

    # DER sig with a leading-zero-padded r: must decode to 64 raw bytes.
    r = b"\x00" + b"\x7f" * 32
    s = b"\x01" * 32
    der = (b"\x30" + bytes([4 + len(r) + len(s)])
           + b"\x02" + bytes([len(r)]) + r
           + b"\x02" + bytes([len(s)]) + s)
    raw = _der_to_raw(der)
    assert len(raw) == 64 and raw[32:] == s

    print("self-test OK")


if __name__ == "__main__":
    main()
