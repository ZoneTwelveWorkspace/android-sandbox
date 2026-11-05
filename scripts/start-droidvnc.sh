#!/bin/bash
# Grant droidVNC-NG its permissions and start it headlessly on the guest's private address.
set -uo pipefail
A="adb -s 172.30.0.2:5555"; PKG=net.christianbeier.droidvnc_ng; PORT="${VNC_PORT:-5900}"
adb connect 172.30.0.2:5555 >/dev/null
$A root >/dev/null 2>&1; sleep 3; adb connect 172.30.0.2:5555 >/dev/null
$A shell cmd appops set $PKG PROJECT_MEDIA allow
# Other services (the MCP server) share this list, so add to it rather than replacing it.
CUR=$($A shell settings get secure enabled_accessibility_services | tr -d "\r")
case "$CUR" in
  *"$PKG/.InputService"*) ;;
  null|"") $A shell settings put secure enabled_accessibility_services $PKG/.InputService ;;
  *) $A shell settings put secure enabled_accessibility_services "$CUR:$PKG/.InputService" ;;
esac
$A shell settings put secure accessibility_enabled 1
# Draw a dot on the phone for every touch, so taps from VNC and MCP are visible on screen.
$A shell settings put system show_touches 1
$A shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null
$A shell dumpsys deviceidle whitelist +$PKG >/dev/null
$A shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 6
KEY=$($A shell "cat /data/data/$PKG/shared_prefs/*.xml" | tr -d '\r' | sed -n 's/.*name="[a-z_]*access_key">\([^<]*\)<.*/\1/p' | head -1)
[ -n "$KEY" ] || { echo "no access key found"; $A shell "ls /data/data/$PKG/shared_prefs" | cut -c1-140; exit 1; }
echo "access key found (${#KEY} chars)"
# The app restores itself at boot and ignores a second start, so stop it first to apply these settings.
$A shell am start-foreground-service -n $PKG/.MainService -a $PKG.ACTION_STOP --es $PKG.EXTRA_ACCESS_KEY "$KEY" >/dev/null 2>&1
sleep 4
$A shell am start-foreground-service -n $PKG/.MainService -a $PKG.ACTION_START \
  --es $PKG.EXTRA_ACCESS_KEY "$KEY" --ei $PKG.EXTRA_PORT "$PORT" --ez $PKG.EXTRA_VIEW_ONLY false --ef $PKG.EXTRA_SCALING 1.0 2>&1 | tail -1 | cut -c1-120
sleep 8
$A shell input keyevent HOME
$A shell "logcat -d -v time -t 300 | grep -iE 'droidvnc|MainService|MediaProjection|InputService' | tail -10" | cut -c1-150
for i in 1 2 3 4 5 6; do timeout 3 bash -c "</dev/tcp/172.30.0.2/$PORT" 2>/dev/null && { echo "VNC port $PORT open"; break; } || sleep 3; done
