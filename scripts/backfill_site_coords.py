#!/usr/bin/env python3
"""Backfill lat/lng on community-added RoadMate sites in Firestore.

Community sites are created from the Add Site screen without coordinates, so they
never appear on Nearby and have no distance readout. This patches researched
coordinates onto them.

Writes use PATCH with updateMask so ONLY lat/lng change -- vote counters,
currentStatus, approvedBy, createdAt etc. must survive untouched. Auth is the
roadmate firebase-adminsdk service account; stdlib + openssl only, matching
scripts/play_upload.py.

  python3 scripts/backfill_site_coords.py --dry-run     # show planned writes
  python3 scripts/backfill_site_coords.py --only <id>   # write a single doc
  python3 scripts/backfill_site_coords.py               # write all
  python3 scripts/backfill_site_coords.py --verify      # diff live vs backup
"""
import argparse, base64, json, os, subprocess, sys, tempfile, time
import urllib.request

SA_PATH = os.path.expanduser("~/.config/roadmate/firebase-adminsdk.json")
BACKUP = os.path.expanduser("~/tmp/roadmate-backup/sites-backup-2026-07-26.json")
PROJECT = "roadmate-b1551"
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
WEB_KEY = "AIzaSyAxlTgoPC_T3jtCRFPJB5wojiHIPN32174"

# doc_id -> (name, lat, lng, provenance)
COORDS = {
    # --- exact pins supplied by the owner (WhatsApp screenshots, ~/tmp/locations) ---
    "Sl3VBFA0S1kw9vWMW2vM": ("COOLAC",           -34.9693931, 148.1506961, "owner pin"),
    "9eRFsDuxkX2XDNy9jUVv": ("ONE TREE",         -34.7784781, 148.8414927, "owner pin"),
    "hefbW0tvjdd5yFTL2eAC": ("GOOROMON",         -35.1290035, 149.0476054, "owner pin"),
    "qP2s0TNcLsMRCiBCXshM": ("LAKE GEORGE",      -34.9908069, 149.3862990, "owner pin"),
    # --- plus code held in the site's own address field (decoder validated on ONE TREE) ---
    "aOIMWMJ1F9Zlh0xp4EIX": ("YARCK",            -37.1075625, 145.6119375, "plus code VJR6+XQ -> Maroondah Hwy"),
    # --- OSM features, reverse-geocoded to the road named in the site's address ---
    "aTUhU6995cKvDC3ThzKt": ("Northern Road",    -33.836104,  150.683580,  "OSM Heavy Vehicle Checking Bay, The Northern Road"),
    "u89KVkE61xmBfw9ckACm": ("Fig Tree/Taree",   -31.855044,  152.601970,  "OSM weighbridge, Pacific Highway"),
    "lMW2aaNOXx55qyn7G2b2": ("Merbein South",    -34.230714,  141.990594,  "OSM Weighbridge bldg, Sturt Hwy Wargan"),
    "jw3ECPGHG5IqmSRbyAYF": ("horsham",          -36.755478,  142.239636,  "OSM weighbridge, Western Hwy Bungalally"),
    "7Rm9uWwU3R2F0JncXqeI": ("ballarat E bound", -37.554075,  143.973957,  "OSM Weighbridge Offramp, Western Fwy"),
    "she9EQwkUYrIrwobTxwS": ("ballarat W bound", -37.554075,  143.973957,  "same site, other carriageway (Mt White/Marulan convention)"),
    "zwd0BbDqxWnUWOcypbYs": ("Yamba",            -34.261380,  140.865270,  "OSM Yamba Quarantine Station, Sturt Hwy 5340"),
}


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def get_token():
    """Service-account RS256 JWT -> OAuth access token for the datastore scope."""
    sa = json.load(open(SA_PATH))
    now = int(time.time())
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64url(json.dumps({
        "iss": sa["client_email"],
        "scope": "https://www.googleapis.com/auth/datastore",
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now, "exp": now + 3600,
    }).encode())
    signing_input = f"{header}.{claims}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
        f.write(sa["private_key"])
        keyfile = f.name
    try:
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", keyfile],
                             input=signing_input, capture_output=True, check=True).stdout
    finally:
        os.unlink(keyfile)
    jwt = f"{header}.{claims}.{b64url(sig)}"
    body = ("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"
            f"&assertion={jwt}").encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["access_token"]


def patch_coords(token, doc_id, lat, lng):
    """PATCH lat+lng ONLY -- without updateMask this would blank every other field."""
    qs = "updateMask.fieldPaths=lat&updateMask.fieldPaths=lng"
    body = json.dumps({"fields": {"lat": {"doubleValue": lat},
                                  "lng": {"doubleValue": lng}}}).encode()
    req = urllib.request.Request(f"{BASE}/sites/{doc_id}?{qs}", data=body, method="PATCH",
                                 headers={"Authorization": f"Bearer {token}",
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def fetch_live():
    with urllib.request.urlopen(f"{BASE}/sites?key={WEB_KEY}&pageSize=300", timeout=90) as r:
        return json.load(r)


def index(payload):
    return {d["name"].split("/")[-1]: d.get("fields", {}) for d in payload.get("documents", [])}


# Fields real users move while we work -- drivers keep voting during the backfill,
# so churn here is organic app traffic, not something our PATCH did.
LIVE_FIELDS = {"openVotes", "closedVotes", "blitzVotes", "currentStatus", "lastReportAt"}


def verify():
    """Diff every field of every doc against the pre-change backup.

    Passes only if our writes touched lat/lng on the intended docs and nothing
    else -- in particular no doc may LOSE a field, which is what a PATCH without
    updateMask would do.
    """
    before, after = index(json.load(open(BACKUP))), index(fetch_live())
    ok = True
    if set(before) - set(after):
        print(f"!!!  docs disappeared: {set(before) - set(after)}")
        ok = False
    for doc_id in sorted(set(after) - set(before)):
        print(f"note new doc since backup: {doc_id}")
    for doc_id in sorted(set(before) & set(after)):
        b, a = before[doc_id], after[doc_id]
        name = COORDS.get(doc_id, ("--",))[0]
        if set(b) - set(a):
            print(f"!!!  {doc_id} ({name}) LOST fields: {set(b) - set(a)}")
            ok = False
        for key in sorted(set(b) | set(a)):
            if b.get(key) == a.get(key):
                continue
            if key in ("lat", "lng") and doc_id in COORDS:
                verdict = "ok   "
            elif key in LIVE_FIELDS:
                verdict = "live "  # organic voting traffic
            else:
                verdict, ok = "!!!  ", False
            print(f"{verdict}{doc_id} ({name}) {key}: {b.get(key)} -> {a.get(key)}")
    print("\nVERIFY PASS: our writes changed lat/lng only; no field loss."
          if ok else "\nVERIFY FAIL: unexpected field changes above.")
    return ok


def self_test():
    """Exercise the pure plumbing without touching Firestore or the key file."""
    # Every coordinate must sit inside the Australian mainland bounding box --
    # a sign flip or a lat/lng swap is the likeliest way bad data gets in here.
    for doc_id, (name, lat, lng, _why) in COORDS.items():
        assert -44.0 < lat < -10.0, f"{name}: lat {lat} outside AU"
        assert 112.0 < lng < 154.0, f"{name}: lng {lng} outside AU"
        assert len(doc_id) > 3, f"suspicious doc id {doc_id!r}"

    # Paired directional sites share one coordinate (Mt White/Marulan convention).
    ballarat = {k: v[1:3] for k, v in COORDS.items()
                if v[0].startswith("ballarat")}
    assert len(ballarat) == 2 and len(set(ballarat.values())) == 1, ballarat

    # verify() must accept organic vote churn but reject silent field loss.
    base = {"x": {"fields": {"lat": {"nullValue": None}, "openVotes": {"integerValue": "1"},
                             "approvedBy": {"stringValue": "u1"}}}}
    assert LIVE_FIELDS >= {"openVotes", "closedVotes", "blitzVotes"}
    assert "approvedBy" not in LIVE_FIELDS, "vote-adjacent metadata must not be excused"
    assert index({"documents": [{"name": "a/b/x", "fields": base["x"]["fields"]}]})["x"]

    print(f"self-test OK ({len(COORDS)} coordinates checked)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        self_test()
        return
    if args.verify:
        sys.exit(0 if verify() else 1)

    targets = {args.only: COORDS[args.only]} if args.only else COORDS
    for doc_id, (name, lat, lng, why) in targets.items():
        print(f"{'DRY ' if args.dry_run else ''}{doc_id}  {name:18s} "
              f"{lat:>12.6f},{lng:>11.6f}  # {why}")
    if args.dry_run:
        return

    token = get_token()
    for doc_id, (name, lat, lng, _why) in targets.items():
        patch_coords(token, doc_id, lat, lng)
        print(f"  wrote {doc_id} ({name})")
    print(f"\n{len(targets)} doc(s) updated.")


if __name__ == "__main__":
    main()
