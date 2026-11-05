#!/bin/bash
# Configure and start the on-device MCP server, with a bearer token. v1.12.0 only accepts 127.0.0.1 or 0.0.0.0;
# in this guest 0.0.0.0 means loopback plus the private /30 tap link, so it is not reachable from outside the Lima VM.
set -uo pipefail
PKG=com.danielealbano.androidremotecontrolmcp; A="adb -s 172.30.0.2:5555"; PORT=8080
GUEST_IP=172.30.0.2; TOKEN_FILE="$HOME/fc/mcp-token"; APK="$HOME/fc/assets/android-remote-control-mcp.apk"
SVC="$PKG/$PKG.services.accessibility.McpAccessibilityService"

[ -s "$TOKEN_FILE" ] || (umask 077; openssl rand -hex 32 > "$TOKEN_FILE")
$A root >/dev/null 2>&1; sleep 2; $A wait-for-device
$A shell pm path "$PKG" >/dev/null 2>&1 || $A install -r "$APK" | tail -1

# droidVNC-NG needs its accessibility service too, so add to the list rather than replacing it.
CUR=$($A shell settings get secure enabled_accessibility_services | tr -d '\r')
case "$CUR" in
  *"$SVC"*) ;;
  null|"") $A shell settings put secure enabled_accessibility_services "$SVC" ;;
  *) $A shell settings put secure enabled_accessibility_services "$CUR:$SVC" ;;
esac
$A shell settings put secure accessibility_enabled 1
$A shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null

# The app's own tunnel would publish the phone through a third party, so it stays off.
$A shell am broadcast -a "$PKG.ADB_CONFIGURE" -n "$PKG/$PKG.services.mcp.AdbConfigReceiver" \
  --es bearer_token "$(cat "$TOKEN_FILE")" --ez bearer_token_enabled true --ez oauth_enabled false \
  --es binding_address 0.0.0.0 --ei port "$PORT" --ez auto_start_on_boot true \
  --ez https_enabled false --ez tunnel_enabled false >/dev/null
# A running server keeps its old settings, so stop it first.
$A shell am start -n "$PKG/$PKG.services.mcp.AdbServiceTrampolineActivity" --es action stop >/dev/null; sleep 2
$A shell am start -n "$PKG/$PKG.services.mcp.AdbServiceTrampolineActivity" --es action start >/dev/null

for _ in $(seq 1 30); do
  CODE=$(curl -s -o /dev/null -m 3 -w '%{http_code}' -X POST "http://$GUEST_IP:$PORT/mcp" || true)
  [ "$CODE" = 401 ] && { echo "MCP listening on $GUEST_IP:$PORT, rejects missing token"; exit 0; }
  sleep 1
done
echo "MCP not ready (last HTTP status: $CODE)"; exit 1
