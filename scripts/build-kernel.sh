#!/bin/bash
# Build a Firecracker 6.18 arm64 guest kernel with the Android fragment merged in.
# Usage: build-kernel.sh <fragment> [source patch...]
set -euo pipefail
FRAGMENT="$(realpath "$1")"; shift
PATCHES=(); for p in "$@"; do PATCHES+=("$(realpath "$p")"); done
SRC="$HOME/fc/kernel"; OUT="$HOME/fc/assets"
mkdir -p "$SRC" "$OUT"; cd "$SRC"
VER="${KERNEL_VER:-6.18.60}"
echo "kernel version: $VER"
SHA256="3c2f44ef6acc021a7ad444d9a2e6ec1ef488ff09368793d0004a6080f69d621e"  # kernel.org sha256sums.asc
TARBALL="linux-$VER.tar.xz"
MIRRORS="${KERNEL_MIRROR:-} https://mirrors.aliyun.com/linux-kernel https://mirrors.tuna.tsinghua.edu.cn/kernel https://cdn.kernel.org/pub/linux/kernel"
until echo "$SHA256  $TARBALL" | sha256sum -c --status 2>/dev/null; do
  for m in $MIRRORS; do
    curl -fL -C - --retry 3 --speed-time 30 --speed-limit 20000 -o "$TARBALL" "$m/v6.x/$TARBALL" && break
  done
  if [ "$(stat -c %s "$TARBALL" 2>/dev/null || echo 0)" -gt 160000000 ] && ! echo "$SHA256  $TARBALL" | sha256sum -c --status; then
    echo "checksum mismatch, discarding $TARBALL"; rm -f "$TARBALL"
  fi
done
echo "checksum verified: $TARBALL"
rm -rf "linux-$VER"; tar -xJf "$TARBALL"
cd "linux-$VER"
for p in ${PATCHES[@]+"${PATCHES[@]}"}; do patch -p1 --no-backup-if-mismatch < "$p"; done
curl -fsSL -o .config https://raw.githubusercontent.com/firecracker-microvm/firecracker/v1.17.0/resources/guest_configs/microvm-kernel-ci-aarch64-6.18.config
scripts/kconfig/merge_config.sh -m .config "$FRAGMENT" >/dev/null
make ARCH=arm64 olddefconfig >/dev/null
echo "--- requested options that did not land:"
while IFS= read -r line; do
  case "$line" in CONFIG_*=n|\#*|"") continue;; esac
  grep -qxF "$line" .config || echo "  $line => $(grep -E "^(# )?${line%%=*}[ =]" .config || echo absent)"
done < "$FRAGMENT"
make ARCH=arm64 -j"$(nproc)" Image 2>&1 | tail -3
cp arch/arm64/boot/Image "$OUT/vmlinux-android"; cp .config "$OUT/vmlinux-android.config"
ls -l "$OUT/vmlinux-android"
