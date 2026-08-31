#!/bin/sh
# Collect everything needed to debug a ddcci setup. Output: /tmp/ddcci-report-*.txt
# Attach that file when filing an issue.
out=/tmp/ddcci-report-$(date +%Y%m%d-%H%M%S).txt
redact=0
[ "${1:-}" = "--redact" ] && redact=1

(
echo "=== ddcci report: $(date -R) ==="
echo "--- system ---"
grep PRETTY /etc/os-release; uname -a
rpm -q gnome-shell mutter gnome-settings-daemon 2>/dev/null

echo; echo "--- dkms / modules ---"
dkms status 2>/dev/null
modinfo ddcci 2>/dev/null | grep -E '^(filename|version|vermagic)'
lsmod | grep ddcci || echo "(modules not loaded)"

echo; echo "--- attach infrastructure ---"
cat /etc/modules-load.d/ddcci.conf 2>/dev/null
cat /etc/udev/rules.d/99-ddcci-attach.rules 2>/dev/null
cat /usr/lib/systemd/system/ddcci-attach.service 2>/dev/null
systemctl status ddcci-attach.service --no-pager 2>&1 | sed -n '1,4p'

echo; echo "--- sysfs state ---"
for b in /sys/class/backlight/*; do
    echo "$b -> $(cat $b/brightness)/$(cat $b/max_brightness), type=$(cat $b/type 2>/dev/null)"
done
for d in /sys/bus/ddcci/devices/*; do
    echo "$d: $(cut -c1-160 $d/capabilities 2>/dev/null)"
done
[ -d /sys/bus/ddcci/devices/ddcci0 ] || true

echo; echo "--- ddcutil detect ---"
ddcutil detect --terse 2>&1

echo; echo "--- ddcutil environment (official diagnostic) ---"
ddcutil environment 2>&1

echo; echo "--- live probe trace (dynamic debug) ---"
    if [ -w /sys/kernel/debug/dynamic_debug/control ]; then
    echo 'module ddcci +p' > /sys/kernel/debug/dynamic_debug/control
    before=$(dmesg | wc -l)
    for d in /sys/bus/ddcci/devices/ddcci*; do
        bus=$(echo "$d" | grep -o '[0-9]*$')
        echo 0x37 > /sys/bus/i2c/devices/i2c-$bus/delete_device 2>/dev/null
    done
    # ddcci bus-device teardown is async: wait until the name is really free
    i=0
    while ls /sys/bus/ddcci/devices/ddcci* >/dev/null 2>&1 && [ $i -lt 20 ]; do
        sleep 0.5; i=$((i + 1))
    done
    ddcutil detect --terse 2>/dev/null | awk '
        /^Display [0-9]/ {inb=1}
        inb && /I2C bus:/ {sub(/.*i2c-/,""); print; inb=0}
    ' | while read -r bus; do
        try=0
        while [ $try -lt 3 ]; do
            echo "ddcci 0x37" > /sys/bus/i2c/devices/i2c-$bus/new_device 2>/dev/null && break
            try=$((try + 1)); sleep 3
        done
    done
    sleep 4
    dmesg | tail -n +$((before + 1)) | grep -i 'ddcci\|i2c.*0037'
else
    echo "(dynamic debug not writable, run with sudo)"
fi
echo; echo "=== end of report ==="
) > "$out" 2>&1

# privacy: strip identifying data unless the user needs full detail
if [ "$redact" = 1 ]; then
    hn=$(hostname)
    sed -i -e "s/$hn/HOSTNAME/g" \
        -e 's/Serial number:.*/Serial number: REDACTED/' \
        -e 's/Binary serial number:.*/Binary serial number: REDACTED/' \
        -e 's/serial=[0-9]*/serial=REDACTED/g' \
        -e 's/\(Monitor: *[^:]*:[^:]*\):.*/\1:REDACTED/' \
        -e 's/edid serial: [0-9]*/edid serial: REDACTED/' \
        -e 's/\(model(\)/\1/' "$out"
fi

echo "Report written: $out"
echo "dmesg probe trace included: $(grep -c 'ddcci' "$out") ddcci lines"
