#!/bin/sh
# Instantiate the ddcci driver on every DDC-capable i2c bus.
# Kernel 6.8+ dropped DDC auto-probing; ddcutil (already quirk-aware)
# is used to find valid buses.
# Exits nonzero if any bus stays unattached -> the systemd unit restarts us.
sleep 2  # let a just-appeared bus settle

scan() {
    ddcutil detect --terse 2>/dev/null | awk '
        /^Display [0-9]/ {inb=1}
        inb && /I2C bus:/ {sub(/.*i2c-/,""); print; inb=0}
    '
}
buses=$(scan)
if [ -z "$buses" ]; then
    # the bus may exist while the monitor is not DDC-ready yet: rescan once
    sleep 8
    buses=$(scan)
    [ -z "$buses" ] && exit 0
fi

rc=0
for bus in $buses; do
    d=/sys/bus/i2c/devices/i2c-$bus
    healthy() { [ -r "/sys/class/backlight/ddcci$bus/brightness" ]; }
    modprobe ddcci-backlight 2>/dev/null || true

    try=0
    until healthy || [ $try -ge 5 ]; do
        # drop a stale client; the ddcci bus-device release is async and
        # can lag for a long while after replug storms (probe hits -17
        # EBUSY on the duplicate name until it finishes) - keep retrying
        if [ -e "$d/${bus}-0037" ]; then
            echo 0x37 > "$d/delete_device" 2>/dev/null || true
        fi
        if [ -w "$d/new_device" ]; then
            echo "ddcci 0x37" > "$d/new_device" 2>/dev/null || true
        fi
        try=$((try + 1))
        sleep 5
    done

    if healthy; then
        echo "ddcci-attach: bus $bus ok"
        continue
    fi

    # last resort: full reset via module unload. Zombie ddcci kobjects
    # left by failed probes can pin the bus-device name indefinitely;
    # unloading the modules drops all of their state in one go.
    modprobe -r ddcci-backlight 2>/dev/null || true
    modprobe -r ddcci 2>/dev/null || true
    sleep 1
    if [ -e "$d/${bus}-0037" ]; then
        echo 0x37 > "$d/delete_device" 2>/dev/null || true
        sleep 1
    fi
    modprobe ddcci-backlight 2>/dev/null || true
    [ -w "$d/new_device" ] && \
        echo "ddcci 0x37" > "$d/new_device" 2>/dev/null || true
    sleep 3

    if healthy; then
        echo "ddcci-attach: bus $bus ok (after module reset)"
    else
        echo "ddcci-attach: bus $bus FAILED after module reset" >&2
        rc=1
    fi
done
exit $rc
