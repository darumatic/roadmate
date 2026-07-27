#!/usr/bin/env bash
# Records the Play Console foreground-service demonstration video on an Android
# emulator. Runs on the Mac (the emulator lives there), not the VPS.
#
#   ./scripts/record_fgs_demo.sh [output.webm]
#
# Why this exists: the FOREGROUND_SERVICE_LOCATION declaration in the Play
# Console wants a video showing the service is user-triggered from the
# foreground and visible to the driver while it runs. The shot list it satisfies
# is in store/play_foreground_service_declaration.md.
#
# Prerequisites:
#   * an emulator running an image with Google Play services (mock GPS + the
#     fused provider that derives speed), e.g.
#       avdmanager create avd -n RoadMate_Pixel8_API35 \
#         -k "system-images;android-35;google_apis_playstore;arm64-v8a" -d pixel_8
#       emulator -avd RoadMate_Pixel8_API35 &
#   * the release APK installed:
#       flutter build apk --release
#       adb install -r build/app/outputs/flutter-apk/app-release.apk
#   * an empty notification shade (the script's frames show RoadMate's own
#     notifications; swipe away anything else first).
#
# Notes on the choreography, all of which cost a take to work out:
#   * POST_NOTIFICATIONS is granted over adb before recording, so the only
#     dialog on camera is the location one the declaration is about.
#   * The grant is a 7 px swipe, not a tap: a tap is delivered to the Flutter
#     view underneath once the dialog closes, which navigates away mid-take.
#   * Movement is simulated with `geo fix <lng> <lat> <alt> <sats> <knots>`.
#     Without the knots argument the fused provider reports speed 0 for most
#     fixes and the approach alert (>= 20 km/h) never fires.
#   * A 2 s cadence is deliberate: at 1 s the derived speed collapses to 0.
#
# Convert for upload with:
#   ffmpeg -i out.webm -an -c:v libx264 -crf 22 -pix_fmt yuv420p out.mp4
set -u

export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/roadmate_fgs_demo.webm}"

PKG=com.darumatic.roadmate
LAT=-33.61565
START_LNG=150.228653   # 3.50 km west of the Mt Boyce site, on the Great Western Hwy
STEP=0.00054           # ~50 m per fix -> 90 km/h at a 2 s cadence
KNOTS=48
DOCK_X=910; DOCK_Y=1969        # RoadMate icon in the launcher dock (1080x2400)
GRANT_X=540; GRANT_Y=1441      # "While using the app" on the location dialog

say() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---------- setup (not recorded) ----------
say "setup: fresh install state, notifications pre-granted, parked 3.5 km out"
adb shell am force-stop $PKG
adb shell pm clear $PKG >/dev/null
adb shell pm revoke $PKG android.permission.ACCESS_FINE_LOCATION
adb shell pm revoke $PKG android.permission.ACCESS_COARSE_LOCATION
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS
adb shell settings put system show_touches 1
adb shell dumpsys battery set level 85 >/dev/null
adb shell dumpsys battery set ac 0 >/dev/null
adb emu geo fix $START_LNG $LAT 1000 12 0 >/dev/null
adb shell cmd statusbar collapse
adb shell input keyevent KEYCODE_HOME
sleep 3

# background driver: one fix every 2 s, heading east toward the site
drive() {
  local lng=$START_LNG
  for _ in $(seq 1 60); do
    lng=$(python3 -c "print(f'{$lng+$STEP:.6f}')")
    adb emu geo fix "$lng" $LAT 1000 12 $KNOTS >/dev/null 2>&1
    sleep 2
  done
}

# ---------- take ----------
say "recording -> $OUT"
adb emu screenrecord start --time-limit 120 --fps 30 "$OUT"
sleep 2

say "1. launch from the launcher"
adb shell input tap $DOCK_X $DOCK_Y
sleep 7

say "2. grant the location permission"
adb shell input swipe $GRANT_X $GRANT_Y $((GRANT_X + 7)) $GRANT_Y 130
sleep 4

say "3. start driving - the speedometer goes live"
drive &
DRIVER=$!
sleep 11

say "4. notification shade: the ongoing service notification"
adb shell input swipe 540 8 540 1400 350
sleep 6
adb shell cmd statusbar collapse
sleep 2

say "5. background the app - the service keeps running"
adb shell input keyevent KEYCODE_HOME
sleep 9

say "6. shade again: service still there, plus the site-approach alert"
adb shell input swipe 540 8 540 1400 350
sleep 7
adb shell cmd statusbar collapse
sleep 1

say "7. reopen: the approach prompt is waiting"
adb shell input tap $DOCK_X $DOCK_Y
sleep 9

adb emu screenrecord stop
kill $DRIVER 2>/dev/null
say "done -> $OUT"
