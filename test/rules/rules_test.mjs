// Verifies the vote/report shapes, admin-delete (issue #13) and
// admin-publish (issue #16) rules in firestore.rules against the Firestore
// emulator. (The issue #15 rate-limit ledger was rolled back — it produced
// false rejections in production.) Run via scripts/test_rules.sh (needs Node
// and Java 21+; not part of `flutter test`).
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  collection,
  doc,
  getDocs,
  increment,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

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

// Mirrors FirestoreSiteRepository.vote().
async function voteBatch(db, siteId, status, uid) {
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
  return b.commit();
}

// Mirrors FirestoreSiteRepository.report().
async function reportBatch(db, siteId, uid) {
  const b = writeBatch(db);
  b.set(doc(collection(db, `sites/${siteId}/reports`)), {
    siteId,
    activityType: 'delays',
    uid,
    createdAt: serverTimestamp(),
  });
  b.update(doc(db, `sites/${siteId}`), { lastReportAt: serverTimestamp() });
  return b.commit();
}

const checks = [];
const check = async (label, promise) => {
  await promise;
  checks.push(label);
  console.log(`ok - ${label}`);
};

// Rate limiting was rolled back: repeated votes/reports in quick succession
// must all succeed (mis-taps can always be corrected).
await check(
  'repeated votes and reports in quick succession all succeed',
  (async () => {
    await assertSucceeds(voteBatch(alice, 'site-1', 'blitz', 'alice'));
    await assertSucceeds(voteBatch(alice, 'site-1', 'open', 'alice'));
    await assertSucceeds(reportBatch(alice, 'site-1', 'alice'));
    await assertSucceeds(reportBatch(alice, 'site-1', 'alice'));
    await assertSucceeds(voteBatch(alice, 'site-2', 'open', 'alice'));
  })(),
);
await check(
  'a tampering counter update (two counters at once) is still rejected',
  assertFails(
    updateDoc(doc(alice, 'sites/site-1'), {
      openVotes: increment(1),
      blitzVotes: increment(1),
      currentStatus: 'open',
      lastReportAt: serverTimestamp(),
    }),
  ),
);
await check(
  'legacy rate-limit ledger docs can no longer be written',
  assertFails(
    setDoc(doc(alice, 'sites/site-1/limits/alice'), {
      windowStart: serverTimestamp(),
      count: 1,
      lastActionAt: serverTimestamp(),
    }),
  ),
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
