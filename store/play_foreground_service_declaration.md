# Play Console — foreground service declaration (v0.1.48+)

Required because `AndroidManifest.xml` declares `FOREGROUND_SERVICE_LOCATION`
(the location-typed service `geolocator_android` runs so site-approach alerts
survive the app being backgrounded). Console-only: **Monitor and improve → App
content → Foreground service permissions**. There is no Play Developer API
endpoint for it, so it cannot be scripted alongside `scripts/release_android.sh`.

`POST_NOTIFICATIONS` needs **no** declaration — it is a runtime permission, not a
foreground service type.

## Use case to select: "Background location updates: Navigation"

**Do not select "Geofencing".** Google is removing geofencing as an approved
`TYPE_LOCATION` use case on **26 August 2026**, directing developers to the
Geofence API instead. A declaration filed under geofencing would be invalidated
within weeks of filing.

Navigation is also the honest fit: the service exists to keep a continuous
position stream running for a driving session — live speed, trip distance, and
en-route site alerts — not to watch a set of static boundaries.

## Description to paste

> RoadMate is a driving companion for Australian heavy-vehicle drivers. While a
> driving session is running, the app uses a location foreground service to keep
> a continuous position stream: it displays live speed and average speed, records
> trip distance and duration, and warns the driver as they approach an NHVR
> inspection or compliance site so they can report and read its live status.
>
> The service is started only while the app is in the foreground and the driver
> has begun a session. It runs at navigation accuracy because the alerts are
> distance-based and must arrive with roughly two minutes of warning at highway
> speed.

**If the system defers or interrupts the task:**

> Location updates stop arriving. The speedometer freezes, trip distance stops
> accumulating, and site alerts are missed entirely — a driver would pass an
> inspection site with no warning, which is the app's core safety function. Because
> alerts are triggered by a shrinking distance measured between consecutive fixes,
> batched or delayed updates are as bad as no updates: the alert would fire after
> the driver has already passed the site.

## Demonstration video — shot list

Keep it under 60 s, no narration needed, screen recording of a real device.
Upload unlisted to YouTube (or a publicly readable Drive link) and paste the URL.

1. Launch RoadMate from the launcher. Home screen visible.
2. Grant the location permission prompt (shows the service is user-triggered from
   the foreground, not started in the background).
3. Show the speedometer going live — "GPS active" and a speed reading.
4. Pull down the notification shade to show the ongoing
   **"RoadMate is watching the road"** service notification. This is the frame
   reviewers look for: the service is visible to the user while running.
5. Press Home to background the app. Show the notification still present in the
   shade — the service continues during the drive.
6. Reopen RoadMate; show the speed still updating.
7. Optional but strongest, if you can drive within 3 km of a site: show the
   approach card (or its notification) appearing with the OPEN / BLITZ / CLOSED
   buttons. Tapping the arrow icon on Home turns the feature off, which is worth
   showing as the user control.

## Also worth checking while you are in App content

The **Data safety** form may now need updating. Before v0.1.48 no location data
left the device (trips are `shared_preferences` only; votes and reports carry a
site id and status, never coordinates). Add Site's "use my current location"
button changes that: it writes the captured latitude/longitude to Firestore under
the user's uid, and `sites/` is world-readable, so a submitted coordinate becomes
public. It is optional and user-initiated, but it is precise location leaving the
device — worth confirming your existing answers still describe the app.

## Alternative considered

Android's Geofence API would remove the foreground service and the ongoing
notification entirely, and is where Google is pointing this use case. It is
better for battery (the OS batches the wake-ups) and there are only ~41 sites
against a 100-geofence limit. The catch: background geofence triggering needs
`ACCESS_BACKGROUND_LOCATION`, whose Play declaration is the harder of the two —
so the foreground service is the cheaper path today. Revisit if the ongoing
notification draws complaints.
