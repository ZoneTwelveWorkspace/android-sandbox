#!/bin/bash
# Serve noVNC on the Lima VM's loopback (Lima forwards it to the Mac's localhost) and bridge to the guest VNC server.
set -euo pipefail
VNC_TARGET="${VNC_TARGET:-172.30.0.2:5900}"; PORT="${WEB_PORT:-6080}"; WEB="$HOME/fc/run/novnc"
# Android sends no pointer shape, so noVNC hides the cursor. Serve a copy that keeps the viewer's own arrow,
# and make the root URL open the phone directly.
rm -rf "$WEB"; cp -rL /usr/share/novnc "$WEB"
sed -i 's|</head>|<style>#noVNC_container canvas { cursor: default !important; }</style></head>|' "$WEB/vnc.html"
echo '<!doctype html><meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=1\&resize=scale">' | sed 's/\\&/\&/' > "$WEB/index.html"
pkill -f "websockify.*$PORT" 2>/dev/null || true
nohup websockify --web "$WEB" "127.0.0.1:$PORT" "$VNC_TARGET" </dev/null >"$HOME/fc/run/webvnc.log" 2>&1 &
echo "noVNC: http://127.0.0.1:$PORT/"
