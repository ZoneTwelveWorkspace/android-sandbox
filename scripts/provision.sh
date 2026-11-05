#!/bin/bash
# Download and build everything Android needs inside the Lima VM. Safe to rerun: finished steps are skipped.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; FC="$HOME/fc"; ASSETS="$FC/assets"; IMAGES="$FC/images"; ROOTFS="$FC/rootfs"
mkdir -p "$FC/bin" "$ASSETS" "$IMAGES" "$FC/run"
step() { echo; echo "=== [$(date +%T)] $*"; }

FC_VER=v1.17.0
FC_SHA=e351ebe4f7a16b5873bbd51005d2e6767103cff4d5ebc829df2d3f95a93e2256
DROIDVNC_VER=v2.22.2
DROIDVNC_SHA=40616318f0918da378afe2def43b9dddf32ae0d481f3564ec944efc5c3cbd1aa
MCP_VER=v1.12.0
MCP_SHA=dd7f1d8997547f1ed04e91a0f32ef97a6e00ad26fb43eb7e5b1cb035e22316f3
REDROID_IMAGE="${REDROID_IMAGE:-docker.io/redroid/redroid@sha256:0a611199ba2e0b5d60af39b3327a517f6407231f4352114ed3bd3cbfe2be69aa}"

fetch() {  # fetch <url> <dest> <sha256>
  echo "$3  $2" | sha256sum -c --status 2>/dev/null && return 0
  curl -fL -C - --retry 5 --retry-all-errors -o "$2" "$1" || { rm -f "$2"; curl -fL --retry 5 -o "$2" "$1"; }
  echo "$3  $2" | sha256sum -c --status || { echo "checksum mismatch: $2"; rm -f "$2"; exit 1; }
}

step "packages"
sudo cloud-init status --wait >/dev/null 2>&1 || true
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  skopeo umoci e2fsprogs build-essential flex bison bc libssl-dev libelf-dev dwarves busybox-static adb \
  novnc websockify socat curl iptables xz-utils openssl python3 >/dev/null
[ -e /dev/kvm ] || { echo "/dev/kvm is missing: nested virtualization is not available"; exit 1; }
sudo chmod 666 /dev/kvm

step "firecracker $FC_VER"
if ! "$FC/bin/firecracker" --version 2>/dev/null | grep -q "${FC_VER#v}"; then
  fetch "https://github.com/firecracker-microvm/firecracker/releases/download/$FC_VER/firecracker-$FC_VER-aarch64.tgz" "$ASSETS/firecracker.tgz" "$FC_SHA"
  tar -xzf "$ASSETS/firecracker.tgz" -C "$ASSETS"
  install -m755 "$ASSETS/release-$FC_VER-aarch64/firecracker-$FC_VER-aarch64" "$FC/bin/firecracker"
  rm -rf "$ASSETS/release-$FC_VER-aarch64"
fi

step "Android apps"
fetch "https://github.com/bk138/droidVNC-NG/releases/download/$DROIDVNC_VER/droidvnc-ng-${DROIDVNC_VER#v}.apk" "$ASSETS/droidvnc.apk" "$DROIDVNC_SHA"
fetch "https://github.com/danielealbano/android-remote-control-mcp/releases/download/$MCP_VER/android-remote-control-mcp-$MCP_VER-foss-release.apk" "$ASSETS/android-remote-control-mcp.apk" "$MCP_SHA"

step "guest kernel"
[ -s "$ASSETS/vmlinux-android" ] || bash "$HERE/build-kernel.sh" "$HERE/../kernel/android.fragment"

step "redroid filesystem"
if [ ! -x "$ROOTFS/init" ]; then
  cd "$IMAGES"; rm -rf bundle
  # Docker Hub drops long transfers on slow links; skopeo keeps finished layers between attempts.
  for i in 1 2 3 4 5 6; do
    skopeo copy --override-arch arm64 --override-os linux "docker://$REDROID_IMAGE" oci:redroid:14 && break
    [ "$i" = 6 ] && { echo "could not download $REDROID_IMAGE"; exit 1; }
    sleep 10
  done
  sudo umoci unpack --image redroid:14 bundle >/dev/null
  sudo rm -rf "$ROOTFS"; sudo mv bundle/rootfs "$ROOTFS"; sudo rm -rf bundle redroid
  cd - >/dev/null
fi

step "disk images"
[ -s "$IMAGES/android-root.ext4" ] || bash "$HERE/build-rootfs.sh"

echo; echo "provision finished at $(date +%T)"
