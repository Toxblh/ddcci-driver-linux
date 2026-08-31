Name: dkms-ddcci
Version: 0.4.5
Release: alt1
Summary: DDC/CI bus and backlight kernel drivers (DKMS)
License: GPL-2.0-or-later
Group: Development/Kernel
BuildArch: noarch

Source: %name-%version.tar

Requires: dkms
Requires: ddcutil

%description
Two Linux kernel drivers for DDC/CI monitors:

* ddcci - bus driver that detects DDC/CI devices on i2c-DDC busses and
  exposes them on /sys/bus/ddcci;
* ddcci-backlight - exposes monitor luminance as a standard
  /sys/class/backlight device, so brightness keys, GNOME/KDE and anything
  else speaking the backlight API control external monitors natively.

Since kernel 6.8 DRM drivers no longer set I2C_CLASS_DDC, so the package
ships a udev rule + systemd service that instantiate the driver on buses
found by ddcutil, and a ddcci-report.sh diagnostic for bug reports.

%prep
%setup -q

%install
mkdir -p %buildroot%_usrsrc/ddcci-%version
cp -a ddcci ddcci-backlight include Makefile dkms.conf LICENSE \
	%buildroot%_usrsrc/ddcci-%version/

install -Dpm755 dist/ddcci-attach.sh  %buildroot%_sbindir/ddcci-attach
install -Dpm755 dist/ddcci-report.sh  %buildroot%_sbindir/ddcci-report
install -Dpm644 dist/ddcci-attach.service %buildroot%_unitdir/ddcci-attach.service
install -Dpm644 dist/99-ddcci-attach.rules %buildroot%_udevrulesdir/99-ddcci-attach.rules
install -Dpm644 dist/ddcci.conf %buildroot/lib/modules-load.d/ddcci.conf

%post
dkms add -m ddcci -v %version >/dev/null 2>&1 ||:
# build/install may fail before matching kernel headers are installed;
# enabled dkms.service retries on every boot.
dkms install -m ddcci -v %version >/dev/null 2>&1 ||:
%systemd_post ddcci-attach.service
udevadm control --reload-rules >/dev/null 2>&1 ||:

%preun
%systemd_preun ddcci-attach.service

%postun
dkms remove -m ddcci -v %version --all >/dev/null 2>&1 ||:
if [ $1 -eq 0 ]; then
	udevadm control --reload-rules >/dev/null 2>&1 ||:
fi
%systemd_postun ddcci-attach.service

%files
%_usrsrc/ddcci-%version
%_sbindir/ddcci-attach
%_sbindir/ddcci-report
%_unitdir/ddcci-attach.service
%_udevrulesdir/99-ddcci-attach.rules
/lib/modules-load.d/ddcci.conf
%doc README.md dist/README-ALT.md

%changelog
* Mon Aug 31 2026 Toxblh <toxblh@altlinux.space> 0.4.5-alt1
- Initial build for ALT: base ddcci-driver-linux 0.4.5 (tastelessjolt fork)
  with kernel 6.18 build fix, Dell U2725QE probe reliability fixes and
  ddcci-backlight read cache / write-reversal suppression.
