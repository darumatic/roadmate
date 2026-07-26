#!/usr/bin/env python3
"""Delete junk/test site documents from the RoadMate Firestore.

Deleting a Firestore document does NOT delete its subcollections, so any
sites/{id}/reports/{id} left behind would keep surfacing in the app's
collectionGroup('reports') query. This removes reports first, then the site.

Irreversible -- back the docs up before running (see BACKUP) and use --dry-run
first. Auth reuses the service-account token helper from the coord backfill.

  python3 scripts/delete_test_sites.py --dry-run
  python3 scripts/delete_test_sites.py --only <id>
  python3 scripts/delete_test_sites.py --verify
"""
import argparse, json, os, sys, urllib.error, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backfill_site_coords import BASE, WEB_KEY, get_token  # noqa: E402

BACKUP = os.path.expanduser("~/tmp/roadmate-backup/deleted-test-sites-2026-07-26.json")

# doc_id -> (name, why it is junk)
TARGETS = {
    "80EtnP9QPhmBlyDtZFOp": ("test",   "NSW; name/suburb/address all 'test'; rejected=true"),
    "CduqI3RXWS2PCSW3YyGW": ("d1",     "NT (non-NHVR); suburb/address 'darwin'; rejected=true"),
    "DOuVGIgOsjx1t1hEfEYQ": ("darwin", "NT (non-NHVR); suburb/address 'darwin'; rejected=true"),
    "ODck9IEZ5uFEQPNUOcZ0": ("d2",     "NT (non-NHVR); was approved & live; 26 test reports"),
}


def list_reports(doc_id):
    url = f"{BASE}/sites/{doc_id}/reports?key={WEB_KEY}&pageSize=300"
    with urllib.request.urlopen(url, timeout=60) as r:
        return [d["name"].split("/")[-1] for d in json.load(r).get("documents", [])]


def delete(token, path):
    req = urllib.request.Request(f"{BASE}/{path}", method="DELETE",
                                 headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status


def exists(path):
    try:
        urllib.request.urlopen(f"{BASE}/{path}?key={WEB_KEY}", timeout=60)
        return True
    except urllib.error.HTTPError as e:
        if e.code in (403, 404):
            return False
        raise


def verify():
    """Every target site and every one of its backed-up reports must be gone."""
    backup = json.load(open(BACKUP))
    ok = True
    for doc_id, (name, _why) in TARGETS.items():
        if exists(f"sites/{doc_id}"):
            print(f"!!!  sites/{doc_id} ({name}) still present")
            ok = False
        else:
            print(f"ok   sites/{doc_id} ({name}) deleted")
        orphans = [r["name"].split("/")[-1] for r in backup.get(doc_id, {}).get("reports", [])
                   if exists(f"sites/{doc_id}/reports/{r['name'].split('/')[-1]}")]
        if orphans:
            print(f"!!!  {len(orphans)} orphaned reports under {doc_id}: {orphans[:5]}")
            ok = False
    print("\nVERIFY PASS: all target sites and their reports are gone." if ok
          else "\nVERIFY FAIL: see above.")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()

    if args.verify:
        sys.exit(0 if verify() else 1)

    targets = {args.only: TARGETS[args.only]} if args.only else TARGETS
    if not os.path.exists(BACKUP):
        sys.exit(f"refusing to delete: no backup at {BACKUP}")

    token = None if args.dry_run else get_token()
    for doc_id, (name, why) in targets.items():
        reports = list_reports(doc_id)
        print(f"{'DRY ' if args.dry_run else ''}{doc_id} ({name}) "
              f"+ {len(reports)} report(s)  # {why}")
        if args.dry_run:
            continue
        for rid in reports:
            delete(token, f"sites/{doc_id}/reports/{rid}")
        if reports:
            print(f"  deleted {len(reports)} report(s)")
        delete(token, f"sites/{doc_id}")
        print(f"  deleted sites/{doc_id} ({name})")


if __name__ == "__main__":
    main()
