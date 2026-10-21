#!/bin/bash
# Installs the APK on the emulator, opens it, logs in as the demo staff, and saves screenshots,
# the screen text and the app's log lines into $OUT.
set -x
OUT=${OUT:-shots}
mkdir -p "$OUT"
adb install -r mangao-wrs.apk
adb logcat -c
adb shell am start -n com.mangao.mangao_wrs/.MainActivity
sleep 40
adb exec-out screencap -p > "$OUT/1-welcome.png"
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml "$OUT/1-welcome.xml"
xy=$(python3 tools/android-test/tap.py "$OUT/1-welcome.xml" text "Log in")
[ -n "$xy" ] && adb shell input tap $xy
sleep 4
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml "$OUT/2-login.xml"
xy=$(python3 tools/android-test/tap.py "$OUT/2-login.xml" edit 0); [ -n "$xy" ] && adb shell input tap $xy && adb shell input text 09170000002
xy=$(python3 tools/android-test/tap.py "$OUT/2-login.xml" edit 1); [ -n "$xy" ] && adb shell input tap $xy && adb shell input text staff123
adb shell input keyevent 111 # close the keyboard
sleep 1
adb exec-out screencap -p > "$OUT/2-login.png"
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml "$OUT/2b-login.xml"
xy=$(python3 tools/android-test/tap.py "$OUT/2b-login.xml" text "Log in" last)
[ -n "$xy" ] && adb shell input tap $xy
sleep 45
adb exec-out screencap -p > "$OUT/3-after-login.png"
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml "$OUT/3-after-login.xml"
# Live Map tab (staff): the map, or "No deliveries running" when nothing is out.
xy=$(python3 tools/android-test/tap.py "$OUT/3-after-login.xml" starts "Live Map")
[ -n "$xy" ] && adb shell input tap $xy
sleep 20
adb exec-out screencap -p > "$OUT/4-live-map.png"
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml "$OUT/4-live-map.xml"
adb logcat -d | grep -i -E "flutter|mangao" > "$OUT/log.txt" || true
grep -o 'text="[^"]\+"' "$OUT/3-after-login.xml" | head -40 > "$OUT/3-screen-text.txt" || true
exit 0
