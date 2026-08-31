#!/bin/sh
# Instantiate the ddcci driver on every DDC-capable i2c bus.
# Kernel 6.8+ dropped DDC auto-probing; ddcutil (already quirk-aware)
# is used to find valid buses.
sleep 2  # let a just-appeared bus settle
ddcutil detect --terse 2>/dev/null | awk '
    /^Display [0-9]/ {inb=1}
    inb && /I2C bus:/ {sub(/.*i2c-/,""); print; inb=0}
' | while read -r bus; do
    d=/sys/bus/i2c/devices/i2c-$bus
    # healthy: ddcci device already attached -> do nothing
    [ -e "/sys/bus/ddcci/devices/ddcci$bus" ] && continue
    # stale i2c client without a ddcci device: remove it first;
    # its ddcci bus-device teardown is async, wait for the name to free
    if [ -e "$d/${bus}-0037" ]; then
        echo 0x37 > "$d/delete_device" 2>/dev/null || true
        i=0
        while [ -e "/sys/bus/ddcci/devices/ddcci$bus" ] && [ $i -lt 20 ]; do
            sleep 0.5; i=$((i + 1))
        done
    fi
    [ -e "/sys/bus/ddcci/devices/ddcci$bus" ] && continue
    [ -w "$d/new_device" ] || continue
    modprobe ddcci-backlight 2>/dev/null || true
    echo "ddcci 0x37" > "$d/new_device" 2>/dev/null \
        || echo "ddcci-attach: no DDC device on bus $bus" >&2
done
