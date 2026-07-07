// Verifies the rate-limit (issue #15), admin-delete (issue #13) and
// admin-publish (issue #16) rules in firestore.rules against the Firestore
// emulator. Run via scripts/test_rules.sh (needs Node and Java 21+; not part
// of `flutter test`).
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  increment,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const WINDOW_MS = 5 * 60_000; // 5 actions per 5 minutes, as in the rules

const env = await initializeTestEnvironment({
  projectId: 'roadmate-b1551',
  firestore: {
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    host: 'localhost',
    port: 8080,
  },
});

const site = (name) => ({
  name,
  state: 'NSW',
  type: 'checkingStation',
  suburb: 'Marulan',
  address: 'Hume Hwy',
  approved: true,
  openVotes: 0,
  blitzVotes: 0,
  closedVotes: 0,
  currentStatus: 'open',
});

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'sites/site-1'), site('Site One'));
  await setDoc(doc(db, 'sites/site-2'), site('Site Two'));
  await setDoc(doc(db, 'userRoles/admin1'), { role: 'admin', email: 'a@b.c' });
});

const alice = env
  .authenticatedContext('alice', { firebase: { sign_in_provider: 'anonymous' } })
  .firestore();

// Mirrors FirestoreSiteRepository._ledgerPayload(): read the ledger, reset
// the window if it ended, otherwise count one more action.
async function ledgerPayload(db, siteId, uid) {
  const snap = await getDoc(doc(db, `sites/${siteId}/limits/${uid}`));
  const data = snap.exists() ? snap.data() : null;
  const windowStart = data?.windowStart ?? null;
  const count = data?.count ?? 0;
  const expired =
    windowStart == null || Date.now() > windowStart.toMillis() + WINDOW_MS;
  return {
    windowStart: expired ? serverTimestamp() : windowStart,
    count: expired ? 1 : count + 1,
    lastActionAt: serverTimestamp(),
  };
}

// Mirrors FirestoreSiteRepository.vote().
async function voteBatch(db, siteId, status, uid) {
  const ledger = await ledgerPayload(db, siteId, uid);
  const b = writeBatch(db);
  b.set(doc(collection(db, `sites/${siteId}/reports`)), {
    siteId,
    status,
    uid,
    createdAt: serverTimestamp(),
  });
  b.update(doc(db, `sites/${siteId}`), {
    [`${status}Votes`]: increment(1),
    currentStatus: status,
    lastReportAt: serverTimestamp(),
  });
  b.set(doc(db, `sites/${siteId}/limits/${uid}`), ledger);
  return b.commit();
}

// Mirrors FirestoreSiteRepository.report().
async function reportBatch(db, siteId, uid) {
  const ledger = await ledgerPayload(db, siteId, uid);
  const b = writeBatch(db);
  b.set(doc(collection(db, `sites/${siteId}/reports`)), {
    siteId,
    activityType: 'delays',
    uid,
    createdAt: serverTimestamp(),
  });
  b.update(doc(db, `sites/${siteId}`), { lastReportAt: serverTimestamp() });
  b.set(doc(db, `sites/${siteId}/limits/${uid}`), ledger);
  return b.commit();
}

const checks = [];
const check = async (label, promise) => {
  await promise;
  checks.push(label);
  console.log(`ok - ${label}`);
};

// Five mixed actions (votes + reports share the window) succeed; the sixth
// is rejected. Undoing a mis-tap right away is explicitly allowed.
await check(
  'undoing a mis-tap works: two votes in quick succession succeed',
  (async () => {
    await assertSucceeds(voteBatch(alice, 'site-1', 'blitz', 'alice'));
    await assertSucceeds(voteBatch(alice, 'site-1', 'open', 'alice'));
  })(),
);
await check(
  'up to five mixed actions per window succeed',
  (async () => {
    await assertSucceeds(reportBatch(alice, 'site-1', 'alice'));
    await assertSucceeds(voteBatch(alice, 'site-1', 'closed', 'alice'));
    await assertSucceeds(reportBatch(alice, 'site-1', 'alice'));
  })(),
);
await check(
  'the sixth action inside the window is rejected',
  assertFails(voteBatch(alice, 'site-1', 'open', 'alice')),
);
await check(
  'a different site is unaffected',
  assertSucceeds(voteBatch(alice, 'site-2', 'open', 'alice')),
);
await check(
  'bare counter bump without a ledger write is rejected',
  assertFails(
    updateDoc(doc(alice, 'sites/site-1'), {
      openVotes: increment(1),
      currentStatus: 'open',
      lastReportAt: serverTimestamp(),
    }),
  ),
);
await check(
  'a forged ledger (fake window or count jump) is rejected',
  (async () => {
    // Backdated windowStart to dodge the cap.
    await assertFails(
      setDoc(doc(alice, 'sites/site-1/limits/alice'), {
        windowStart: Timestamp.fromDate(new Date(Date.now() - 3600_000)),
        count: 1,
        lastActionAt: serverTimestamp(),
      }),
    );
    // Same window but count not incremented.
    await assertFails(
      setDoc(doc(alice, 'sites/site-1/limits/alice'), {
        windowStart: (
          await getDoc(doc(alice, 'sites/site-1/limits/alice'))
        ).data().windowStart,
        count: 5,
        lastActionAt: serverTimestamp(),
      }),
    );
  })(),
);
await check(
  "another user's ledger cannot be written",
  assertFails(
    setDoc(doc(alice, 'sites/site-1/limits/bob'), {
      windowStart: serverTimestamp(),
      count: 1,
      lastActionAt: serverTimestamp(),
    }),
  ),
);

// Once the window has genuinely passed, actions work again (backdate the
// ledger with rules disabled to simulate the wait).
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), 'sites/site-1/limits/alice'), {
    windowStart: Timestamp.fromDate(new Date(Date.now() - 6 * 60_000)),
    count: 5,
    lastActionAt: Timestamp.fromDate(new Date(Date.now() - 6 * 60_000)),
  });
});
await check(
  'a new window opens after 5 minutes and actions succeed again',
  assertSucceeds(voteBatch(alice, 'site-1', 'closed', 'alice')),
);

// Issue #13 rules: admin site delete (with subcollections), non-admin denied.
await check(
  'non-admin cannot delete a site',
  assertFails(
    (() => {
      const b = writeBatch(alice);
      b.delete(doc(alice, 'sites/site-2'));
      return b.commit();
    })(),
  ),
);
const admin = env
  .authenticatedContext('admin1', { email: 'a@b.c' })
  .firestore();
await check(
  'admin deletes a site with its reports and limits',
  assertSucceeds(
    (async () => {
      const b = writeBatch(admin);
      for (const col of ['reports', 'limits']) {
        const docs = await getDocs(collection(admin, `sites/site-2/${col}`));
        docs.forEach((d) => b.delete(d.ref));
      }
      b.delete(doc(admin, 'sites/site-2'));
      return b.commit();
    })(),
  ),
);

// Issue #16 rules: site creation — pending for everyone, approved only for
// admins.
const newSite = (uid, approved) => ({
  name: 'New Yard',
  state: 'NSW',
  type: 'checkingStation',
  suburb: 'Broome',
  address: 'Hwy 1',
  approved,
  createdBy: uid,
});
await check(
  'anonymous user creates a pending site',
  assertSucceeds(setDoc(doc(alice, 'sites/pending-1'), newSite('alice', false))),
);
await check(
  'anonymous user cannot create an approved site',
  assertFails(setDoc(doc(alice, 'sites/sneaky-1'), newSite('alice', true))),
);
await check(
  'admin creates an approved (published) site',
  assertSucceeds(
    setDoc(doc(admin, 'sites/admin-1'), {
      ...newSite('admin1', true),
      approvedAt: serverTimestamp(),
      approvedBy: 'admin1',
    }),
  ),
);

console.log(`\nALL ${checks.length} RULES CHECKS PASSED`);
await env.cleanup();
