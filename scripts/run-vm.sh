#!/bin/bash
# Boot Android in Firecracker. ADB and VNC stay on the private tap network; only noVNC is forwarded.
set -euo pipefail
FC="$HOME/fc"; RUN="$FC/run"; TAP=android-tap0
VCPUS="${VCPUS:-6}"; MEM_MIB="${MEM_MIB:-4096}"; HUGE="${HUGE:-2M}"
KERNEL="${KERNEL:-$FC/assets/vmlinux-android}"; GPU_MODE="${GPU_MODE:-guest}"
# Screen refresh, 1 to 60. Set with ./avm fps; everything is drawn on the CPU, so lower it if the VM is overloaded.
FPS="${FPS:-$(cat "$FC/fps" 2>/dev/null || echo 30)}"
case "$FPS" in ([1-9]|[1-5][0-9]|60) ;; (*) echo "FPS must be 1 to 60, got $FPS"; exit 1 ;; esac
mkdir -p "$RUN"
pkill -f "firecracker --api-sock $RUN/fc.sock" 2>/dev/null || true
rm -f "$RUN/fc.sock"

sudo ip link del "$TAP" 2>/dev/null || true
sudo ip tuntap add dev "$TAP" mode tap user "$(id -un)"
sudo ip addr add 172.30.0.1/30 dev "$TAP"
sudo ip link set "$TAP" up
sudo sysctl -qw net.ipv4.ip_forward=1
UPLINK=$(ip route show default | awk '{print $5; exit}')
sudo iptables -t nat -C POSTROUTING -s 172.30.0.0/30 -o "$UPLINK" -j MASQUERADE 2>/dev/null \
  || sudo iptables -t nat -A POSTROUTING -s 172.30.0.0/30 -o "$UPLINK" -j MASQUERADE
sudo iptables -C FORWARD -i "$TAP" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -i "$TAP" -j ACCEPT
sudo iptables -C FORWARD -o "$TAP" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -o "$TAP" -j ACCEPT

# 2M guest backing cuts the stage-2 faults that are very costly under nested virtualization.
MACHINE_EXTRA=""
if [ "$HUGE" = 2M ]; then
  sudo sysctl -qw vm.nr_hugepages=$(( MEM_MIB / 2 + 8 ))
  [ "$(awk '/HugePages_Total/{print $2}' /proc/meminfo)" -ge $(( MEM_MIB / 2 )) ] || { echo "could not reserve huge pages"; exit 1; }
  MACHINE_EXTRA=', "huge_pages": "2M"'
fi

BOOT_ARGS="console=ttyS0 reboot=k panic=1 root=/dev/vda rw rootfstype=ext4 init=/fc-init selinux=0 psi=1 quiet loglevel=3 \
androidboot.hardware=redroid androidboot.use_memfd=1 androidboot.redroid_gpu_mode=$GPU_MODE \
androidboot.redroid_width=480 androidboot.redroid_height=854 androidboot.redroid_dpi=240 androidboot.redroid_fps=$FPS \
androidboot.redroid_net_ndns=1 androidboot.redroid_net_dns1=8.8.8.8"

cat > "$RUN/config.json" <<JSON
{
  "boot-source": {"kernel_image_path": "$KERNEL", "boot_args": "$BOOT_ARGS"},
  "drives": [
    {"drive_id": "rootfs", "path_on_host": "$FC/images/android-root.ext4", "is_root_device": true, "is_read_only": false},
    {"drive_id": "data", "path_on_host": "$FC/images/android-data.ext4", "is_root_device": false, "is_read_only": false}
  ],
  "network-interfaces": [{"iface_id": "eth0", "guest_mac": "06:FC:30:00:00:02", "host_dev_name": "$TAP"}],
  "machine-config": {"vcpu_count": $VCPUS, "mem_size_mib": $MEM_MIB, "smt": false$MACHINE_EXTRA}
}
JSON
# Serial console stdin is a FIFO so the guest stays reachable when Android has its network down.
rm -f "$RUN/console.in"; mkfifo "$RUN/console.in"
pkill -f "[s]leep infinity.*console-hold" 2>/dev/null || true
nohup bash -c "exec 3<>'$RUN/console.in'; exec sleep infinity" console-hold >/dev/null 2>&1 &
# Firecracker installs its own SIGHUP handler, so nohup is not enough: it needs its own session.
setsid nohup "$FC/bin/firecracker" --api-sock "$RUN/fc.sock" --config-file "$RUN/config.json" \
  <"$RUN/console.in" >"$RUN/console.log" 2>&1 &
echo "firecracker pid $!, console log: $RUN/console.log"
