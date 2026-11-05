#!/bin/bash
# Boot the Android microVM, wait for it, then start VNC, MCP and their bridges. Run inside the Lima VM.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; A="adb -s 172.30.0.2:5555"; START=$(date +%s)
sudo chmod 666 /dev/kvm
bash "$HERE/run-vm.sh" || exit 1
adb kill-server >/dev/null 2>&1; adb start-server >/dev/null 2>&1
until [ "$(timeout 10 $A shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
  [ $(( $(date +%s)-START )) -gt 1500 ] && { echo "boot timed out"; exit 1; }
  timeout 5 adb connect 172.30.0.2:5555 >/dev/null 2>&1; sleep 3
done
echo "boot_completed after $(( $(date +%s)-START ))s"
bash "$HERE/setup-android.sh"
bash "$HERE/start-droidvnc.sh" | grep -E "VNC port|no access key"
timeout 3 bash -c "</dev/tcp/172.30.0.2/5900" 2>/dev/null || { echo "VNC server did not start"; exit 1; }
bash "$HERE/start-mcp.sh" || exit 1
bash "$HERE/run-webvnc.sh"
bash "$HERE/run-mcp-forward.sh"
echo "ready after $(( $(date +%s)-START ))s"
