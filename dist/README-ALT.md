# ddcci-driver-linux (ALT edition)

Fork of the DDC/CI kernel drivers ([upstream](https://github.com/ddcci-driver-linux/ddcci-driver-linux),
deleted; based on [tastelessjolt's fork](https://github.com/tastelessjolt/ddcci-driver-linux))
with fixes needed on modern kernels and one picky monitor:

## Patches on top of 0.4.5

1. **kernel 6.18**: `bus_type.match` takes `const struct device_driver *`.
2. **probe reliability (Dell U2725QE over USB-C AUX)**:
   - single `0x00` byte write resets the monitor's DDC FIFO before identify
     (same trick ddcutil uses);
   - identify and capabilities exchanges retry both the write and the read —
     the monitor NACKs or corrupts frames while recovering from other bus
     traffic.
3. **ddcci-backlight**:
   - brightness reads are served from cache (~75 ms DDC read made GNOME's
     slider bounce on read-back);
   - rapid direction reversals (<200 ms) are suppressed from reaching the
     monitor — gnome-shell fights itself through `logind SetBrightness` at
     slider extremes and on fast drags; real drags are monotonic and pass
     through unchanged.

## Kernel 6.8+: no auto-probing

DRM drivers stopped setting `I2C_CLASS_DDC`, so the bus driver cannot find
displays by itself. The package ships:

- `ddcci-attach.service` — finds DDC-capable buses with `ddcutil detect`
  and instantiates `ddcci 0x37` on each (idempotent, safe on hotplug);
- a udev rule that triggers the service when an i2c bus appears;
- `modules-load.d` entry for the two modules.

After installing matching kernel headers the enabled `dkms.service` builds
the module for the running kernel on boot.

## Diagnostics

`sudo ddcci-report.sh` collects system info, dkms status, sysfs state,
`ddcutil environment` and a dynamic-debug hex trace of a live re-probe —
one file, enough for a bug report.

## Building the ALT package

```
git archive --format=tar --prefix=dkms-ddcci-0.4.5/ HEAD \
	> dkms-ddcci-0.4.5.tar
rpmbuild -ba dist/dkms-ddcci.spec  # with the tarball in ~/rpmbuild/SOURCES
```

Or just push — CI (`.forgejo/workflows/rpm.yml`) builds it on ALS runners.
