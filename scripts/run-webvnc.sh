#!/bin/bash
# Serve noVNC on the Lima VM's loopback (Lima forwards it to the Mac's localhost) and bridge to the guest VNC server.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VNC_TARGET="${VNC_TARGET:-172.30.0.2:5900}"; PORT="${WEB_PORT:-6080}"; WEB="$HOME/fc/run/novnc"
# Android sends no pointer shape, so noVNC hides the cursor. Serve a copy that draws its own arrow,
# and make the root URL open the phone directly. Bump the v= value when the page changes, to get past browser caches.
URL="vnc.html?autoconnect=1&resize=scale&v=2"
rm -rf "$WEB"; cp -rL /usr/share/novnc "$WEB"; cp "$HERE/novnc-cursor.js" "$WEB/"
sed -i 's|</head>|<style>#noVNC_container canvas { cursor: none !important; }</style><script src="novnc-cursor.js"></script></head>|' "$WEB/vnc.html"
printf '<!doctype html><meta http-equiv="refresh" content="0; url=%s">\n' "$URL" > "$WEB/index.html"
pkill -f "websockify.*$PORT" 2>/dev/null || true
nohup websockify --web "$WEB" "127.0.0.1:$PORT" "$VNC_TARGET" </dev/null >"$HOME/fc/run/webvnc.log" 2>&1 &
echo "noVNC: http://127.0.0.1:$PORT/$URL"
