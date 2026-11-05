#!/bin/bash
# Build guest/gralloc-shim.c and install it over redroid's gralloc module in the unpacked filesystem.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; HW="$HOME/fc/rootfs/vendor/lib64/hw"; B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
# The shim assumes this module layout, so leave other Android versions' modules alone rather than break their boot.
SRC="$HW/gralloc.redroid.so"; sudo test -e "$HW/gralloc.redroid-real.so" && SRC="$HW/gralloc.redroid-real.so"
SIZE="$(sudo nm -DS "$SRC" 2>/dev/null | awk '$4 == "HMI" {print $2}')"
if [ "$((16#${SIZE:-0}))" != 688 ]; then echo "gralloc shim skipped: unexpected module (HMI size 0x${SIZE:-none})"; exit 0; fi
# Link against empty stand-ins: Android supplies the real libraries at load time, and no Android toolchain is needed.
for l in libc libdl liblog; do
  echo > "$B/empty.c"; gcc -shared -nostdlib -fPIC -Wl,-soname,$l.so "$B/empty.c" -o "$B/$l.so"
done
gcc -O2 -shared -fPIC -nostdlib -fno-stack-protector -mno-outline-atomics -fvisibility=hidden -Wl,--hash-style=both -Wl,-z,noexecstack \
  -Wl,--allow-shlib-undefined -Wl,--unresolved-symbols=ignore-all -Wl,--no-as-needed -Wl,-soname,gralloc.redroid.so \
  "$HERE/../guest/gralloc-shim.c" -L"$B" -lc -ldl -llog -o "$B/gralloc.redroid.so"
sudo test -e "$HW/gralloc.redroid-real.so" || sudo mv "$HW/gralloc.redroid.so" "$HW/gralloc.redroid-real.so"
sudo install -m644 "$B/gralloc.redroid.so" "$HW/gralloc.redroid.so"
echo "gralloc shim installed"
