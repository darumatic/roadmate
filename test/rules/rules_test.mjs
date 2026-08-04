// Verifies the vote/report shapes, admin-delete (issue #13), admin-publish
// (issue #16), the admin broadcast notice (announcements/current) and the
// global per-user rate-limit ledger (issue #15 redux:
// 5 actions per 5 minutes at users/{uid}/limits/actions, judged entirely by
// request.time, admins exempt) rules in firestore.rules against the Firestore
// emulator.
// Run via scripts/test_rules.sh (needs Node and Java 21+) or the CI
// rules-test job; not part of `flutter test`.
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  collection,
  collectionGroup,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  increment,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
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
  await setDoc(doc(db, 'users/alice'), {
    email: 'alice@example.com',
    isAnonymous: false,
  });
  await setDoc(doc(db, 'users/alice/favourites/site-1'), {
    favouritedAt: serverTimestamp(),
  });
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

// The new-client shapes: same action batches plus the global ledger stamp
// (mirrors FirestoreSiteRepository._commitWithLedgerStamp).
const ledgerDoc = (db, uid) => doc(db, `users/${uid}/limits/actions`);

function stampIncrement(b, db, uid) {
  b.update(ledgerDoc(db, uid), {
    count: increment(1),
    lastActionAt: serverTimestamp(),
  });
}

function stampReset(b, db, uid) {
  b.set(ledgerDoc(db, uid), {
    count: 1,
    windowStart: serverTimestamp(),
    lastActionAt: serverTimestamp(),
  });
}

async function stampedVote(db, siteId, status, uid, stamp) {
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
  stamp(b, db, uid);
  return b.commit();
}

async function stampedReport(db, siteId, uid, stamp) {
  const b = writeBatch(db);
  b.set(doc(collection(db, `sites/${siteId}/reports`)), {
    siteId,
    activityType: 'delays',
    uid,
    createdAt: serverTimestamp(),
  });
  b.update(doc(db, `sites/${siteId}`), { lastReportAt: serverTimestamp() });
  stamp(b, db, uid);
  return b.commit();
}

const checks = [];
const check = async (label, promise) => {
  await promise;
  checks.push(label);
  console.log(`ok - ${label}`);
};

// RETROCOMPAT (phase 1 of issue #15 redux): released mobile builds commit
// plain 2-op batches with no ledger stamp and must keep succeeding without
// any frequency limit.
await check(
  'legacy unstamped votes and reports in quick succession all succeed',
  (async () => {
    await assertSucceeds(voteBatch(alice, 'site-1', 'blitz', 'alice'));
    await assertSucceeds(voteBatch(alice, 'site-1', 'open', 'alice'));
    await assertSucceeds(reportBatch(alice, 'site-1', 'alice'));
    await assertSucceeds(reportBatch(alice, 'site-1', 'alice'));
    await assertSucceeds(voteBatch(alice, 'site-2', 'open', 'alice'));
  })(),
);

// The shared recent-reports listener (read-cost work): every client — not
// just admins — may run the 10h collectionGroup('reports') query that feeds
// all site cards from a single subscription.
await check(
  'any client runs the shared recent-reports collectionGroup query',
  assertSucceeds(
    getDocs(
      query(
        collectionGroup(alice, 'reports'),
        where(
          'createdAt',
          '>=',
          Timestamp.fromDate(new Date(Date.now() - 10 * 3_600_000)),
        ),
        orderBy('createdAt', 'desc'),
        limit(500),
      ),
    ),
  ),
);

// ---- Rate-limit ledger (issue #15 redux) ----
const admin = env
  .authenticatedContext('admin1', { email: 'a@b.c' })
  .firestore();
const bob = env
  .authenticatedContext('bob', { firebase: { sign_in_provider: 'anonymous' } })
  .firestore();

await check(
  'increment before any ledger exists fails (client falls back to reset)',
  assertFails(stampedVote(bob, 'site-1', 'open', 'bob', stampIncrement)),
);
await check(
  'first stamped action creates the ledger via the reset shape',
  assertSucceeds(stampedVote(bob, 'site-1', 'open', 'bob', stampReset)),
);
await check(
  'actions 2-5 increment the open window — votes and reports, any site',
  (async () => {
    await assertSucceeds(stampedVote(bob, 'site-1', 'blitz', 'bob', stampIncrement));
    await assertSucceeds(stampedReport(bob, 'site-1', 'bob', stampIncrement));
    await assertSucceeds(stampedReport(bob, 'site-2', 'bob', stampIncrement));
    await assertSucceeds(stampedVote(bob, 'site-2', 'closed', 'bob', stampIncrement));
  })(),
);
await check(
  'the 6th action inside the window is denied in both shapes (global limit)',
  (async () => {
    await assertFails(stampedVote(bob, 'site-2', 'open', 'bob', stampIncrement));
    await assertFails(stampedVote(bob, 'site-2', 'open', 'bob', stampReset));
    await assertFails(stampedReport(bob, 'site-1', 'bob', stampIncrement));
  })(),
);
await check(
  'an exhausted ledger still does not block legacy unstamped batches',
  assertSucceeds(voteBatch(bob, 'site-1', 'open', 'bob')),
);

// Window expiry: the emulator clock cannot be advanced, so age the window by
// backdating it with rules disabled — valid because the rules only compare
// stored timestamps against the server's request.time.
await env.withSecurityRulesDisabled(async (ctx) => {
  await updateDoc(doc(ctx.firestore(), 'users/bob/limits/actions'), {
    windowStart: Timestamp.fromDate(new Date(Date.now() - 6 * 60_000)),
  });
});
await check(
  'once the window expires, increment is denied but reset starts fresh',
  (async () => {
    await assertFails(stampedVote(bob, 'site-1', 'open', 'bob', stampIncrement));
    await assertSucceeds(stampedVote(bob, 'site-1', 'open', 'bob', stampReset));
  })(),
);

// Admins are exempt from the cap: moderating a blitz is a burst of actions.
// The first stamp still has to be a reset — an update() on a ledger doc that
// does not exist yet fails the batch precondition, not the rules.
await check(
  'an admin keeps acting past the cap — no ledger limit at all',
  (async () => {
    await assertSucceeds(
      stampedVote(admin, 'site-1', 'open', 'admin1', stampReset),
    );
    for (let i = 0; i < 4; i++) {
      await assertSucceeds(
        stampedVote(admin, 'site-1', 'blitz', 'admin1', stampIncrement),
      );
    }
    // Actions 6, 7 and 8 — the ones the cap would refuse for anyone else.
    await assertSucceeds(
      stampedVote(admin, 'site-1', 'closed', 'admin1', stampIncrement),
    );
    await assertSucceeds(stampedReport(admin, 'site-1', 'admin1', stampIncrement));
    await assertSucceeds(
      stampedVote(admin, 'site-2', 'open', 'admin1', stampIncrement),
    );
  })(),
);

// Forged ledgers: every shortcut around the counter must be rejected.
const carol = env
  .authenticatedContext('carol', { firebase: { sign_in_provider: 'anonymous' } })
  .firestore();
await check(
  'forged ledgers are rejected in every variation',
  (async () => {
    // Fresh create claiming a bigger allowance or a client-chosen clock.
    await assertFails(
      setDoc(ledgerDoc(carol, 'carol'), {
        count: 3,
        windowStart: serverTimestamp(),
        lastActionAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(ledgerDoc(carol, 'carol'), {
        count: 1,
        windowStart: Timestamp.fromDate(new Date(Date.now() - 10 * 60_000)),
        lastActionAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(ledgerDoc(carol, 'carol'), {
        count: 1,
        windowStart: serverTimestamp(),
        lastActionAt: serverTimestamp(),
        bonus: true,
      }),
    );
    // Legitimate ledger, then tampered increments (bob is at count 1).
    await assertFails(
      updateDoc(ledgerDoc(bob, 'bob'), {
        count: increment(2),
        lastActionAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(ledgerDoc(bob, 'bob'), {
        count: increment(1),
        windowStart: serverTimestamp(), // moving the window mid-increment
        lastActionAt: serverTimestamp(),
      }),
    );
    // Another user's ledger is untouchable, and unreadable by strangers.
    await assertFails(
      setDoc(ledgerDoc(carol, 'bob'), {
        count: 1,
        windowStart: serverTimestamp(),
        lastActionAt: serverTimestamp(),
      }),
    );
    await assertFails(getDoc(ledgerDoc(carol, 'bob')));
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

// Admin activity-report edits: only activityType/activityNote/reporterName
// may change, the doc must stay a valid activity report, and status votes
// stay immutable (their counters live on the site doc).
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'sites/site-1/reports/act-1'), {
    siteId: 'site-1',
    activityType: 'delays',
    activityNote: 'roadworks',
    uid: 'alice',
    createdAt: Timestamp.now(),
  });
  await setDoc(doc(db, 'sites/site-1/reports/vote-1'), {
    siteId: 'site-1',
    status: 'open',
    uid: 'alice',
    createdAt: Timestamp.now(),
  });
});
const actRef = (db) => doc(db, 'sites/site-1/reports/act-1');
await check(
  'non-admin cannot edit an activity report',
  assertFails(updateDoc(actRef(alice), { activityNote: 'defaced' })),
);
await check(
  'admin edits an activity report type and note',
  assertSucceeds(
    updateDoc(actRef(admin), {
      activityType: 'policePresent',
      activityNote: 'patrol car on the shoulder',
    }),
  ),
);
await check(
  'admin clears an activity note',
  assertSucceeds(updateDoc(actRef(admin), { activityNote: deleteField() })),
);
await check(
  'admin edit cannot touch identity fields or forge the shape',
  (async () => {
    await assertFails(updateDoc(actRef(admin), { uid: 'someone-else' }));
    await assertFails(
      updateDoc(actRef(admin), { createdAt: serverTimestamp() }),
    );
    await assertFails(updateDoc(actRef(admin), { siteId: 'site-2' }));
    await assertFails(updateDoc(actRef(admin), { activityType: 'invented' }));
    await assertFails(
      updateDoc(actRef(admin), { activityNote: 'x'.repeat(501) }),
    );
  })(),
);
await check(
  'status votes stay immutable even for admins',
  (async () => {
    const voteRef = doc(admin, 'sites/site-1/reports/vote-1');
    await assertFails(updateDoc(voteRef, { activityType: 'delays' }));
    await assertFails(updateDoc(voteRef, { activityNote: 'note on a vote' }));
  })(),
);

// Bulk purge (AdminRepository.deleteRecentReportsByUser): the admin clears
// every report one uid posted inside the 10h window. It needs three things
// from the rules — the uid-filtered collectionGroup query, the per-doc
// deletes, and the site-tally recount that rides in the same batch.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const [id, siteId] of [
    ['spam-1', 'site-1'],
    ['spam-2', 'site-1'],
  ]) {
    await setDoc(doc(db, `sites/${siteId}/reports/${id}`), {
      siteId,
      status: 'blitz',
      uid: 'spammer',
      createdAt: Timestamp.now(),
    });
  }
});
await check(
  'admin queries one user\'s recent reports across every site',
  assertSucceeds(
    getDocs(
      query(
        collectionGroup(admin, 'reports'),
        where('uid', '==', 'spammer'),
        where(
          'createdAt',
          '>=',
          Timestamp.fromMillis(Date.now() - 10 * 60 * 60 * 1000),
        ),
      ),
    ),
  ),
);
await check(
  'non-admin cannot delete someone else\'s report',
  assertFails(deleteDoc(doc(alice, 'sites/site-1/reports/spam-1'))),
);
await check(
  'admin purges a user\'s reports and recounts the site in one batch',
  assertSucceeds(
    (() => {
      const b = writeBatch(admin);
      b.delete(doc(admin, 'sites/site-1/reports/spam-1'));
      b.delete(doc(admin, 'sites/site-1/reports/spam-2'));
      b.update(doc(admin, 'sites/site-1'), {
        openVotes: 1,
        blitzVotes: 0,
        closedVotes: 0,
        currentStatus: 'open',
        lastReportAt: Timestamp.now(),
      });
      return b.commit();
    })(),
  ),
);

// App config (forced-update gate): world-readable, never client-writable —
// not even by admins; the doc is edited only in the console/Admin SDK.
await check(
  'config is readable pre-auth and unwritable by clients',
  (async () => {
    await assertSucceeds(
      getDoc(doc(env.unauthenticatedContext().firestore(), 'config/app')),
    );
    await assertFails(setDoc(doc(alice, 'config/app'), { minVersion: '9.9.9' }));
    await assertFails(setDoc(doc(admin, 'config/app'), { minVersion: '9.9.9' }));
  })(),
);

// ---- Admin broadcast (announcements/current) ----
// One world-readable doc, written only by admins. Read must work pre-auth so
// the banner shows for anonymous users; the shape is capped and server-stamped
// exactly like a ban.
const announcement = (extra = {}) => ({
  message: 'Signing in is now required to report.',
  severity: 'info',
  publishedAt: serverTimestamp(),
  publishedBy: 'admin1',
  ...extra,
});

await check(
  'anyone reads the admin notice, including pre-auth',
  (async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'announcements/current'), {
        message: 'seeded',
        severity: 'info',
      });
    });
    await assertSucceeds(
      getDoc(doc(env.unauthenticatedContext().firestore(), 'announcements/current')),
    );
    await assertSucceeds(getDoc(doc(alice, 'announcements/current')));
  })(),
);

await check(
  'only an admin publishes or clears a notice',
  (async () => {
    await assertFails(setDoc(doc(alice, 'announcements/current'), announcement()));
    await assertFails(deleteDoc(doc(alice, 'announcements/current')));
    await assertSucceeds(
      setDoc(doc(admin, 'announcements/current'), announcement()),
    );
    // Publishing again replaces the live notice — that is how a typo is fixed.
    await assertSucceeds(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ message: 'Corrected.', severity: 'warning' }),
      ),
    );
    await assertSucceeds(deleteDoc(doc(admin, 'announcements/current')));
  })(),
);

await check(
  'malformed notices are rejected in every variation',
  (async () => {
    // Empty and over-long messages.
    await assertFails(
      setDoc(doc(admin, 'announcements/current'), announcement({ message: '' })),
    );
    await assertFails(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ message: 'x'.repeat(281) }),
      ),
    );
    // Unknown severity, back-dated stamp, forged author, stray field.
    await assertFails(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ severity: 'critical' }),
      ),
    );
    await assertFails(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ publishedAt: Timestamp.fromDate(new Date(0)) }),
      ),
    );
    await assertFails(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ publishedBy: 'alice' }),
      ),
    );
    await assertFails(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ pinned: true }),
      ),
    );
    // expiresAt must be a timestamp when present.
    await assertFails(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ expiresAt: 'next week' }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(admin, 'announcements/current'),
        announcement({ expiresAt: Timestamp.fromDate(new Date('2099-01-01')) }),
      ),
    );
    await assertSucceeds(deleteDoc(doc(admin, 'announcements/current')));
  })(),
);

// ---- Bans (spam control) ----
// An admin writes bans/{uid}; while it is active that uid may not write
// anything. Reads stay open, and so does everything the user needs to leave:
// deleting favourites, the ledger and their own profile.
const spammer = env
  .authenticatedContext('spammer', {
    firebase: { sign_in_provider: 'anonymous' },
  })
  .firestore();

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users/spammer'), { isAnonymous: true });
  await setDoc(doc(db, 'users/spammer/favourites/site-1'), {
    favouritedAt: serverTimestamp(),
  });
});

await check(
  'an unbanned user posts normally',
  (async () => {
    await assertSucceeds(voteBatch(spammer, 'site-1', 'open', 'spammer'));
    await assertSucceeds(reportBatch(spammer, 'site-1', 'spammer'));
  })(),
);

await check(
  'only an admin can write a ban, and the shape is validated',
  (async () => {
    // Self-service unbanning, or banning someone else, is not a thing.
    await assertFails(
      setDoc(doc(spammer, 'bans/alice'), {
        createdAt: serverTimestamp(),
        createdBy: 'spammer',
      }),
    );
    // createdBy must be the acting admin, and createdAt server time.
    await assertFails(
      setDoc(doc(admin, 'bans/spammer'), {
        createdAt: serverTimestamp(),
        createdBy: 'someone-else',
      }),
    );
    await assertFails(
      setDoc(doc(admin, 'bans/spammer'), {
        createdAt: Timestamp.fromDate(new Date(0)),
        createdBy: 'admin1',
      }),
    );
    // No smuggling extra fields in, and the reason is capped.
    await assertFails(
      setDoc(doc(admin, 'bans/spammer'), {
        createdAt: serverTimestamp(),
        createdBy: 'admin1',
        role: 'admin',
      }),
    );
    await assertFails(
      setDoc(doc(admin, 'bans/spammer'), {
        createdAt: serverTimestamp(),
        createdBy: 'admin1',
        reason: 'x'.repeat(201),
      }),
    );
  })(),
);

// A one-day ban: mirrors AdminRepository.banUser(BanDuration.oneDay).
await check(
  'an admin bans a user for a day',
  assertSucceeds(
    setDoc(doc(admin, 'bans/spammer'), {
      until: Timestamp.fromDate(new Date(Date.now() + 24 * 3_600_000)),
      reason: 'vote spam',
      createdAt: serverTimestamp(),
      createdBy: 'admin1',
    }),
  ),
);

await check(
  'a banned user cannot vote, report, add a site, save a favourite or '
    + 'sync their profile',
  (async () => {
    await assertFails(voteBatch(spammer, 'site-1', 'blitz', 'spammer'));
    await assertFails(reportBatch(spammer, 'site-1', 'spammer'));
    await assertFails(
      stampedVote(spammer, 'site-1', 'open', 'spammer', stampReset),
    );
    await assertFails(
      setDoc(doc(collection(spammer, 'sites')), {
        name: 'Spam Yard',
        state: 'NSW',
        type: 'checkingStation',
        address: 'Nowhere',
        approved: false,
        createdBy: 'spammer',
      }),
    );
    await assertFails(
      setDoc(doc(spammer, 'users/spammer/favourites/site-2'), {
        favouritedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(
        doc(spammer, 'users/spammer'),
        { lastSeenAt: serverTimestamp() },
        { merge: true },
      ),
    );
  })(),
);

// The ban takes nothing away that the user needs to read the app — or to
// leave it (App Store 5.1.1(v) deletion must never be blocked).
await check(
  'a banned user still reads sites, sees their own ban, and can delete their '
    + 'account',
  (async () => {
    await assertSucceeds(getDoc(doc(spammer, 'sites/site-1')));
    await assertSucceeds(getDoc(doc(spammer, 'bans/spammer')));
    await assertSucceeds(
      deleteDoc(doc(spammer, 'users/spammer/favourites/site-1')),
    );
    await assertSucceeds(deleteDoc(doc(spammer, 'users/spammer')));
  })(),
);

await check(
  'a ban is private to its owner and the admins',
  (async () => {
    await assertFails(getDoc(doc(alice, 'bans/spammer')));
    await assertSucceeds(getDoc(doc(admin, 'bans/spammer')));
  })(),
);

// An expired 1-day ban stops biting on its own — no admin action, no cron.
await check(
  'an expired ban lets the user post again',
  (async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'bans/spammer'), {
        until: Timestamp.fromDate(new Date(Date.now() - 60_000)),
        createdAt: serverTimestamp(),
        createdBy: 'admin1',
      });
    });
    await assertSucceeds(voteBatch(spammer, 'site-1', 'open', 'spammer'));
  })(),
);

// Forever: a doc with no `until` at all.
await check(
  'a permanent ban (no expiry) blocks posting until an admin lifts it',
  (async () => {
    await assertSucceeds(
      setDoc(doc(admin, 'bans/spammer'), {
        createdAt: serverTimestamp(),
        createdBy: 'admin1',
      }),
    );
    await assertFails(voteBatch(spammer, 'site-1', 'open', 'spammer'));
    await assertFails(deleteDoc(doc(spammer, 'bans/spammer')));
    await assertSucceeds(deleteDoc(doc(admin, 'bans/spammer')));
    await assertSucceeds(voteBatch(spammer, 'site-1', 'open', 'spammer'));
  })(),
);

// RETROCOMPAT: everyone else's writes are untouched by the ban machinery —
// shipped mobile builds know nothing about bans and must keep working.
await check(
  'an unbanned user is unaffected while someone else is banned',
  (async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'bans/spammer'), {
        createdAt: serverTimestamp(),
        createdBy: 'admin1',
      });
    });
    // site-1, not site-2: the admin site-removal check above deletes site-2,
    // and voting on a missing doc fails for its own unrelated reason.
    await assertSucceeds(voteBatch(alice, 'site-1', 'blitz', 'alice'));
    await assertSucceeds(reportBatch(alice, 'site-1', 'alice'));
  })(),
);

// ---- Participation stats (points/levels — purely cosmetic) ----
// New clients bump users/{uid}/stats/participation by exactly one action in
// the same batch as every vote/report, and stamp the author's level into
// activity reports as reporterLevel. Old clients do neither; both shapes
// must pass forever (retrocompat), which the legacy checks above already pin.
const statsDoc = (db, uid) => doc(db, `users/${uid}/stats/participation`);

// Mirrors the statsIncrementPayload(...) write in FirestoreSiteRepository:
// set(merge) + increments, both counters always present.
function stampStats(b, db, uid, kind) {
  b.set(
    statsDoc(db, uid),
    {
      votes: increment(kind === 'vote' ? 1 : 0),
      reports: increment(kind === 'report' ? 1 : 0),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

// The complete new-client shapes: action + site touch + ledger + stats.
async function fullVote(db, siteId, status, uid, stamp) {
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
  stamp(b, db, uid);
  stampStats(b, db, uid, 'vote');
  return b.commit();
}

async function fullReport(db, siteId, uid, stamp, reporterLevel) {
  const b = writeBatch(db);
  b.set(doc(collection(db, `sites/${siteId}/reports`)), {
    siteId,
    activityType: 'delays',
    uid,
    createdAt: serverTimestamp(),
    ...(reporterLevel === undefined ? {} : { reporterLevel }),
  });
  b.update(doc(db, `sites/${siteId}`), { lastReportAt: serverTimestamp() });
  stamp(b, db, uid);
  stampStats(b, db, uid, 'report');
  return b.commit();
}

const dave = env
  .authenticatedContext('dave', { firebase: { sign_in_provider: 'anonymous' } })
  .firestore();

await check(
  'new-client vote and report batches (ledger + stats + reporterLevel) pass',
  (async () => {
    await assertSucceeds(fullVote(dave, 'site-1', 'open', 'dave', stampReset));
    await assertSucceeds(
      fullReport(dave, 'site-1', 'dave', stampIncrement, 1),
    );
    // A report without reporterLevel stays valid — stats alone don't force it.
    await assertSucceeds(
      fullReport(dave, 'site-1', 'dave', stampIncrement, undefined),
    );
  })(),
);

await check(
  'a forged reporterLevel is rejected in every variation',
  (async () => {
    await assertFails(fullReport(dave, 'site-1', 'dave', stampIncrement, 0));
    await assertFails(fullReport(dave, 'site-1', 'dave', stampIncrement, 100));
    await assertFails(
      fullReport(dave, 'site-1', 'dave', stampIncrement, 'Legend'),
    );
    // Status votes never carry a level — no author row ever shows one.
    await assertFails(
      (() => {
        const b = writeBatch(dave);
        b.set(doc(collection(dave, 'sites/site-1/reports')), {
          siteId: 'site-1',
          status: 'open',
          uid: 'dave',
          createdAt: serverTimestamp(),
          reporterLevel: 2,
        });
        b.update(doc(dave, 'sites/site-1'), {
          openVotes: increment(1),
          currentStatus: 'open',
          lastReportAt: serverTimestamp(),
        });
        return b.commit();
      })(),
    );
  })(),
);

await check(
  'stats tampering is rejected in every variation',
  (async () => {
    // Seeding a fat counter from nothing.
    await assertFails(
      setDoc(statsDoc(carol, 'carol'), {
        votes: 500,
        reports: 0,
        updatedAt: serverTimestamp(),
      }),
    );
    // dave sits at votes:1, reports:2 — jumps, decrements, stray keys and
    // client-chosen clocks are all refused.
    await assertFails(
      updateDoc(statsDoc(dave, 'dave'), {
        votes: increment(5),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(statsDoc(dave, 'dave'), {
        votes: increment(-1),
        reports: increment(2),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(statsDoc(dave, 'dave'), {
        votes: increment(1),
        legend: true,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(statsDoc(dave, 'dave'), {
        votes: increment(1),
        updatedAt: Timestamp.fromDate(new Date(0)),
      }),
    );
  })(),
);

await check(
  'a standalone +1 passes — the documented soft-validation ceiling',
  // No getAfter() linkage is possible retrocompatibly (see the rules
  // comment); a scripted +1 earns points no faster than a scripted real
  // vote, which the ledger caps. This check pins the accepted tradeoff.
  assertSucceeds(
    updateDoc(statsDoc(dave, 'dave'), {
      votes: increment(1),
      reports: increment(0),
      updatedAt: serverTimestamp(),
    }),
  ),
);

await check(
  'stats are private to their owner (plus admins) and untouchable by others',
  (async () => {
    await assertSucceeds(getDoc(statsDoc(dave, 'dave')));
    await assertSucceeds(getDoc(statsDoc(admin, 'dave')));
    await assertFails(getDoc(statsDoc(carol, 'dave')));
    await assertFails(
      setDoc(statsDoc(carol, 'dave'), {
        votes: increment(1),
        reports: increment(0),
        updatedAt: serverTimestamp(),
      }, { merge: true }),
    );
  })(),
);

await check(
  'a banned user earns nothing: full new-shape batch and bare stats refused',
  (async () => {
    // spammer holds the permanent ban re-created by the retrocompat check.
    await assertFails(fullVote(spammer, 'site-1', 'open', 'spammer', stampReset));
    await assertFails(
      setDoc(statsDoc(spammer, 'spammer'), {
        votes: 1,
        reports: 0,
        updatedAt: serverTimestamp(),
      }),
    );
  })(),
);

await check(
  'owner and admin can delete a stats doc (account deletion / purge)',
  (async () => {
    await assertFails(deleteDoc(statsDoc(carol, 'dave')));
    await assertSucceeds(deleteDoc(statsDoc(dave, 'dave')));
    // Recreate legitimately, then an admin purges it.
    await assertSucceeds(
      setDoc(statsDoc(dave, 'dave'), {
        votes: 0,
        reports: 1,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(deleteDoc(statsDoc(admin, 'dave')));
  })(),
);

// sitesAdded (0.1.60, Trailblazer badge): a site submission credits the
// third counter in the same batch. The checks above pin the 0.1.59 shapes
// (votes/reports only) — both directions must keep passing.
function stampStatsSiteAdd(b, db, uid) {
  b.set(
    statsDoc(db, uid),
    {
      votes: increment(0),
      reports: increment(0),
      sitesAdded: increment(1),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

await check(
  'adding a site credits sitesAdded in the same batch',
  (async () => {
    // dave's stats doc was purged by the delete check above, so this batch
    // exercises the 4-key seed shape end-to-end.
    const b = writeBatch(dave);
    b.set(doc(dave, 'sites/pending-dave-1'), {
      name: 'Dave Yard',
      state: 'NSW',
      type: 'checkingStation',
      address: 'Hwy 1',
      approved: false,
      createdBy: 'dave',
    });
    stampStatsSiteAdd(b, dave, 'dave');
    await assertSucceeds(b.commit());
    // A 0.1.59-shaped increment (no sitesAdded key at all) still lands on
    // the 4-key doc — get() defaults keep old web tabs posting.
    await assertSucceeds(
      updateDoc(statsDoc(dave, 'dave'), {
        votes: increment(1),
        reports: increment(0),
        updatedAt: serverTimestamp(),
      }),
    );
  })(),
);

await check(
  'sitesAdded tampering is rejected in every variation',
  (async () => {
    await assertFails(
      updateDoc(statsDoc(dave, 'dave'), {
        sitesAdded: increment(5),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(statsDoc(dave, 'dave'), {
        sitesAdded: increment(-1),
        votes: increment(2),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(statsDoc(carol, 'carol'), {
        votes: 0,
        reports: 0,
        sitesAdded: 50,
        updatedAt: serverTimestamp(),
      }),
    );
  })(),
);

// In-app account deletion (App Store 5.1.1(v)): a user erases their own
// favourites and profile doc in one batch; strangers cannot touch either.
const mallory = env
  .authenticatedContext('mallory', { firebase: { sign_in_provider: 'anonymous' } })
  .firestore();
await check(
  'stranger cannot delete another user profile',
  assertFails(deleteDoc(doc(mallory, 'users/alice'))),
);
await check(
  'stranger cannot delete another user favourite',
  assertFails(deleteDoc(doc(mallory, 'users/alice/favourites/site-1'))),
);
await check(
  'stranger cannot delete another user rate-limit ledger',
  assertFails(deleteDoc(ledgerDoc(mallory, 'bob'))),
);
await check(
  'account deletion batch: self deletes favourites, ledger, then profile',
  assertSucceeds(
    (() => {
      const b = writeBatch(alice);
      b.delete(doc(alice, 'users/alice/favourites/site-1'));
      // Blind ledger + stats deletes, mirroring AuthController.deleteAccount —
      // alice never stamped either, so this also proves absent-doc deletes pass.
      b.delete(ledgerDoc(alice, 'alice'));
      b.delete(statsDoc(alice, 'alice'));
      b.delete(doc(alice, 'users/alice'));
      return b.commit();
    })(),
  ),
);

// ---- Road names (0.1.61): usernames/{key} claims, signed votes, profile
// username, submitter name on new sites ----
const claimData = (uid, username) => ({
  uid,
  username,
  createdAt: serverTimestamp(),
});
const claim = (db, key, data) => setDoc(doc(db, `usernames/${key}`), data);

await check(
  'anonymous user claims a road name (claim + profile in one batch)',
  assertSucceeds(
    (() => {
      const b = writeBatch(alice);
      b.set(doc(alice, 'usernames/dusty nomad'), claimData('alice', 'Dusty Nomad'));
      b.set(
        doc(alice, 'users/alice'),
        { username: 'Dusty Nomad', isAnonymous: true, lastSeenAt: serverTimestamp() },
        { merge: true },
      );
      return b.commit();
    })(),
  ),
);

await check(
  'a second user cannot take a claimed name',
  assertFails(claim(bob, 'dusty nomad', claimData('bob', 'Dusty Nomad'))),
);

await check(
  'owner may re-stamp their claim with new casing',
  assertSucceeds(claim(alice, 'dusty nomad', claimData('alice', 'DUSTY Nomad'))),
);

await check(
  'malformed road-name claims are refused',
  (async () => {
    // uid mismatch
    await assertFails(claim(bob, 'big rig', claimData('alice', 'Big Rig')));
    // key does not match username.lower()
    await assertFails(claim(bob, 'big rig', claimData('bob', 'Big Rig X')));
    // too short / too long
    await assertFails(claim(bob, 'xy', claimData('bob', 'xy')));
    await assertFails(claim(bob, 'a'.repeat(31), claimData('bob', 'a'.repeat(31))));
    // forbidden character and bad edge character
    await assertFails(claim(bob, 'bad!name', claimData('bob', 'bad!name')));
    await assertFails(claim(bob, '-big rig', claimData('bob', '-Big Rig')));
    // smuggled extra key
    await assertFails(
      setDoc(doc(bob, 'usernames/big rig'), {
        uid: 'bob',
        username: 'Big Rig',
        createdAt: serverTimestamp(),
        extra: 1,
      }),
    );
    // back-dated createdAt
    await assertFails(
      setDoc(doc(bob, 'usernames/big rig'), {
        uid: 'bob',
        username: 'Big Rig',
        createdAt: Timestamp.fromDate(new Date(0)),
      }),
    );
  })(),
);

await check(
  'renaming releases the old claim in the same batch',
  assertSucceeds(
    (() => {
      const b = writeBatch(alice);
      b.delete(doc(alice, 'usernames/dusty nomad'));
      b.set(
        doc(alice, 'usernames/outback legend'),
        claimData('alice', 'Outback Legend'),
      );
      b.set(
        doc(alice, 'users/alice'),
        { username: 'Outback Legend', isAnonymous: true, lastSeenAt: serverTimestamp() },
        { merge: true },
      );
      return b.commit();
    })(),
  ),
);

await check(
  'anyone may read a claim; stranger cannot delete it; admin can',
  (async () => {
    await assertSucceeds(getDoc(doc(mallory, 'usernames/outback legend')));
    await assertFails(deleteDoc(doc(mallory, 'usernames/outback legend')));
    await assertSucceeds(deleteDoc(doc(admin, 'usernames/outback legend')));
  })(),
);

await env.withSecurityRulesDisabled(async (ctx) => {
  // No `until` == permanent ban.
  await setDoc(doc(ctx.firestore(), 'bans/troll'), {});
});
const troll = env
  .authenticatedContext('troll', { firebase: { sign_in_provider: 'anonymous' } })
  .firestore();
await check(
  'a banned user cannot claim a road name',
  assertFails(claim(troll, 'troll king', claimData('troll', 'Troll King'))),
);

// Mirrors FirestoreSiteRepository.vote() with a signature (0.1.61 clients).
async function signedVoteBatch(db, siteId, status, uid, reporterName) {
  const b = writeBatch(db);
  b.set(doc(collection(db, `sites/${siteId}/reports`)), {
    siteId,
    status,
    uid,
    createdAt: serverTimestamp(),
    reporterName,
  });
  b.update(doc(db, `sites/${siteId}`), {
    [`${status}Votes`]: increment(1),
    currentStatus: status,
    lastReportAt: serverTimestamp(),
  });
  return b.commit();
}

await check(
  'a status vote signed with reporterName is accepted (and legacy unsigned '
    + 'votes still pass)',
  (async () => {
    await assertSucceeds(
      signedVoteBatch(alice, 'site-1', 'open', 'alice', 'Dusty Nomad'),
    );
    await assertSucceeds(voteBatch(alice, 'site-1', 'open', 'alice'));
  })(),
);

await check(
  'a vote with a malformed reporterName is refused',
  (async () => {
    await assertFails(signedVoteBatch(alice, 'site-1', 'open', 'alice', ''));
    await assertFails(
      signedVoteBatch(alice, 'site-1', 'open', 'alice', 'x'.repeat(81)),
    );
    await assertFails(signedVoteBatch(alice, 'site-1', 'open', 'alice', 42));
  })(),
);

await check(
  'profile username must be a 3-30 char string (legacy 5-key sync unaffected)',
  (async () => {
    await assertFails(
      setDoc(doc(bob, 'users/bob'), { username: 'ab', isAnonymous: true }),
    );
    await assertFails(
      setDoc(doc(bob, 'users/bob'), {
        username: 'x'.repeat(31),
        isAnonymous: true,
      }),
    );
    await assertSucceeds(
      setDoc(doc(bob, 'users/bob'), {
        username: 'Big Rig Bob',
        isAnonymous: true,
        lastSeenAt: serverTimestamp(),
      }),
    );
    // The shipped clients' profile-sync shape, untouched.
    await assertSucceeds(
      setDoc(doc(bob, 'users/bob'), {
        email: 'bob@example.com',
        displayName: 'Bob',
        photoUrl: null,
        isAnonymous: false,
        lastSeenAt: serverTimestamp(),
      }),
    );
  })(),
);

await check(
  'a new site may carry the submitter road name; malformed ones are refused',
  (async () => {
    const pending = (createdByName) => ({
      name: 'Named Yard',
      state: 'NSW',
      type: 'checkingStation',
      address: 'Hume Hwy',
      approved: false,
      createdBy: 'alice',
      createdByName,
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(
      setDoc(doc(alice, 'sites/named-site'), pending('Dusty Nomad')),
    );
    await assertFails(setDoc(doc(alice, 'sites/named-site-2'), pending('')));
    await assertFails(
      setDoc(doc(alice, 'sites/named-site-3'), pending('x'.repeat(81))),
    );
  })(),
);

console.log(`\nALL ${checks.length} RULES CHECKS PASSED`);
await env.cleanup();
