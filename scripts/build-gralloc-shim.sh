#!/bin/bash
# Build guest/gralloc-shim.c and install it over redroid's gralloc module in the unpacked filesystem.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; HW="$HOME/fc/rootfs/vendor/lib64/hw"; B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
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
