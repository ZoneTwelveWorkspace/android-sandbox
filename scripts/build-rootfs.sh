#!/bin/bash
# Package the unpacked redroid filesystem into Firecracker ext4 disks.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HOME/fc/rootfs"; OUT="$HOME/fc/images"
ROOT_MB="${ROOT_MB:-4096}"; DATA_MB="${DATA_MB:-8192}"
mkdir -p "$OUT"
sudo mkdir -p "$ROOT/fc"
sudo install -m755 "$(command -v busybox)" "$ROOT/fc/busybox"
sudo install -m755 "$HERE/../guest/fc-init" "$ROOT/fc-init"
bash "$HERE/build-gralloc-shim.sh"
if [ "${DEBUG:-0}" = 1 ]; then
  sudo install -m644 "$HERE/../guest/fc-debug.rc" "$ROOT/vendor/etc/init/fc-debug.rc"
  sudo install -m755 "$HERE/../guest/fc-watch.sh" "$ROOT/vendor/bin/fc-watch.sh"
fi
# Nested virtualization is slow enough that Android's watchdog otherwise kills system_server mid-boot.
sudo grep -q '^ro.hw_timeout_multiplier=' "$ROOT/vendor/build.prop" \
  || echo 'ro.hw_timeout_multiplier=20' | sudo tee -a "$ROOT/vendor/build.prop" >/dev/null
rm -f "$OUT/android-root.ext4"; truncate -s "${ROOT_MB}M" "$OUT/android-root.ext4"
sudo mkfs.ext4 -q -F -L android-root -d "$ROOT" "$OUT/android-root.ext4"
sudo chown "$(id -u):$(id -g)" "$OUT/android-root.ext4"
if [ ! -f "$OUT/android-data.ext4" ] || [ "${RESET_DATA:-0}" = 1 ]; then
  rm -f "$OUT/android-data.ext4"; truncate -s "${DATA_MB}M" "$OUT/android-data.ext4"
  mkfs.ext4 -q -F -L android-data "$OUT/android-data.ext4"
fi
ls -lhs "$OUT"/android-*.ext4
