#!/bin/bash
# Stop Android and its bridges. The Lima VM keeps running.
timeout 10 adb -s 172.30.0.2:5555 shell sync 2>/dev/null
pkill -f "[w]ebsockify" 2>/dev/null
pkill -f "[s]ocat TCP-LISTEN" 2>/dev/null
pkill -x firecracker 2>/dev/null
pkill -f "[s]leep infinity" 2>/dev/null
echo "stopped"
