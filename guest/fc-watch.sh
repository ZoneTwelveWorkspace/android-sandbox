#!/system/bin/sh
# Append a status snapshot every 20s for offline diagnosis.
dmesg -w > /data/fc-dmesg.txt 2>&1 &
while true; do
  {
    echo "=== $(date) up: $(cat /proc/uptime) load: $(cat /proc/loadavg)"
    echo "boot=$(getprop sys.boot_completed) zygote=$(getprop init.svc.zygote) ss=$(getprop init.svc.system_server) vnc=$(getprop init.svc.vendor.vncserver) anim=$(getprop init.svc.bootanim)"
    echo "stream=$(getprop ro.boot.use_redroid_stream) vncflag=$(getprop ro.boot.use_redroid_vnc) vnc=$(getprop init.svc.vendor.vncserver) uinputd=$(getprop init.svc.vendor.uinputd) hwc=$(getprop init.svc.vendor.hwcomposer-3) dex=$(getprop sys.bootstat.first_boot_completed)"
    ls -l /ipc 2>&1 | tail -4
    ip rule | head -12
    ip -br addr show eth0; ip route show table all | grep -E 'default' | head -3
    grep MemAvailable /proc/meminfo
    cat /proc/pressure/cpu /proc/pressure/memory 2>&1 | head -2
    ps -A -o PID,PCPU,RSS,TIME,CMD | sort -k2 -nr | head -6
  } >> /data/fc-status.txt 2>&1
  sleep 20
done
