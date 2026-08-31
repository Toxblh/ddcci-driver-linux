#!/bin/sh
# Install dkms-ddcci from the altlinux.space package registry.
# Works on ALT Atomic (apm) and regular ALT (apt-get).
# Usage: curl -fsSL <raw-url>/install-alt.sh | sudo sh
set -e

[ "$(id -u)" = 0 ] || { echo 'run as root (sudo sh)' >&2; exit 1; }

# match repo group to the system branch (fallback: sisyphus, package is noarch)
branch=$(grep -rhoE '(sisyphus|p1[01])' /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list 2>/dev/null | head -1)
[ -n "$branch" ] || branch=sisyphus
repo="https://altlinux.space/api/packages/toxblh/alt/group/$branch.repo"

echo "==> package repo: $repo"
echo "rpm $repo noarch classic" > /etc/apt/sources.list.d/ddcci-toxblh.list

kv=$(uname -r | cut -d. -f1-2)

if command -v apm >/dev/null; then          # ALT Atomic
    apm system update
    rpm -q "kernel-headers-modules-$kv" >/dev/null 2>&1 || \
        apm system install -y "kernel-headers-modules-$kv"
    rpm -q dkms-ddcci >/dev/null 2>&1 || \
        apm system install -y dkms-ddcci
else                                        # regular ALT
    apt-get update
    apt-get install -y "kernel-headers-modules-$kv" dkms-ddcci
fi

# make sure the module is built for the running kernel
modinfo ddcci >/dev/null 2>&1 || dkms install ddcci/0.4.5 --force

udevadm trigger --subsystem-match=i2c-dev -c add ||:
systemctl enable --now ddcci-attach.service
systemctl start ddcci-attach.service

if ls /sys/class/backlight/ | grep -q '^ddcci'; then
    echo "==> OK: $(ls /sys/class/backlight/ | grep '^ddcci' | tr '\n' ' ')"
    echo "==> brightness keys and GNOME slider should now control external monitors"
else
    echo '==> ddcci backlight did not appear; collect a report:'
    echo '    sudo ddcci-report.sh'
    exit 1
fi
