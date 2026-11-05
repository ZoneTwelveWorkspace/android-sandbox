#!/bin/bash
# First-boot setup of a new /data disk: install the VNC app and turn off apps a headless sandbox does not need.
set -uo pipefail
A="adb -s 172.30.0.2:5555"; PKG=net.christianbeier.droidvnc_ng
$A root >/dev/null 2>&1; sleep 2; adb connect 172.30.0.2:5555 >/dev/null; $A wait-for-device
[ "$($A shell 'cat /data/local/fc-setup-done 2>/dev/null' | tr -d '\r')" = 1 ] && exit 0
echo "first boot: setting up Android"
$A shell pm path "$PKG" >/dev/null 2>&1 || $A install -r -g "$HOME/fc/assets/droidvnc.apk" | tail -1
$A shell settings put global device_provisioned 1
$A shell settings put secure user_setup_complete 1
for p in documentsui egg bluetooth localtransport providers.calendar traceur provision contacts dreams.basic nfc music \
         wallpaper.livepicker camera2 calendar bips managedprovisioning printspooler deskclock dreams.phototable gallery3d; do
  $A shell pm disable-user --user 0 "com.android.$p" >/dev/null 2>&1 || true
done
$A shell 'echo 1 > /data/local/fc-setup-done'
