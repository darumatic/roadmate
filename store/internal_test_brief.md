# RoadMate internal test brief — 0.1.48 (48)

Forward this to the tester. Written for the site-approach-alerts release; reuse
the structure for later ones.

## Before they start

1. **Add their Google account** to the `roadmate` tester list: Play Console →
   Test and release → Testing → Internal testing → Testers. They must be signed
   in to the Play Store with that exact account.
2. Send them the opt-in link:
   **https://play.google.com/apps/internaltest/4701612009237019404**
   → "Become a tester" → install from Play. It can take up to an hour to appear.
3. They should confirm the Info tab shows **v0.1.48** before testing.

Heads-up: this build drops support for 7 devices that 0.1.47 supported. If Play
says the app is incompatible with their phone, that's this — tell us the model.

**Safety:** this is a driving app. Everything except the approach alert can be
tested parked. For the driving parts, use a passenger or a cradle — no phone
handling while driving.

## What to test

### 1. Trip start and the ongoing notification — MOST IMPORTANT

This is the one we could not get working on an emulator, so it is the priority.

- Home → **Start New Trip**.
- Does the speedometer stop saying **"GPS idle"** and start showing a speed?
- Does an ongoing notification (**"RoadMate is watching the road"**) appear in
  the notification shade?

**If either of those does not happen, stop and report it** — that would be a
real bug in this release, not a testing problem.

### 2. Background behaviour

- With a trip running, press Home to leave the app.
- Is the ongoing notification still in the shade?
- Travel a few hundred metres, reopen the app: has trip distance/speed advanced?

### 3. Site-approach alert (needs driving)

Fires only when **all three** are true: within **3 km** of an NHVR site,
**getting closer** to it, and above **20 km/h**.

- Driving toward a site, does a prompt appear asking for its status with
  **OPEN / BLITZ / CLOSED**?
- With the app off screen, it should arrive as a **system notification**
  instead; tapping a button should open the app and record the vote.
- It should fire **at most once per site**, and not at all when parked or
  driving away.

### 4. The on/off control

The **arrow icon** on the Home screen turns approach alerts off and on. Check
both states stick.

### 5. Add Site GPS capture

Add Site → use current location → do latitude/longitude get filled in? (Sites
submitted this way stay pending until approved, so it won't show up publicly.)

### 6. Quick regression pass

Speedometer accuracy vs the car, over-limit beep, Nearby list, voting on a site,
favourites.

## What to send back

Device model, Android version, and for anything that failed: what they did, what
they expected, what happened. Screenshots or a screen recording help.

## Bonus: the Play demo video

If they are willing, a screen recording of steps 1–2 (launch → grant location →
start trip → speedometer live → pull down the shade showing the ongoing
notification → press Home → notification still there) is exactly the video Play
requires for the foreground-service declaration. See
`play_foreground_service_declaration.md` for the full shot list. Under 60
seconds, no narration needed.
