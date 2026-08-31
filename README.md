# ddcci-driver-linux (revived fork) #

The original upstream repository (`github.com/ddcci-driver-linux/ddcci-driver-linux`)
was deleted from GitHub. This tree continues
[tastelessjolt's fork](https://github.com/tastelessjolt/ddcci-driver-linux)
(upstream 0.4.5 + its 6.6/6.10 fixes) and adds the work below, plus ALT Linux
packaging in `dist/`.

## What is added on top ##

1. **Linux 6.18 build fix** — `bus_type.match` now takes a `const struct device_driver *`.
2. **Probe reliability for DDC monitors behind USB-C/TBT (tested on Dell U2725QE)**:
   - a single `0x00` byte write resets the monitor's DDC FIFO before
     identification (the same trick `ddcutil` uses in its `i2c_detect_x37`);
   - identification and capabilities exchanges retry both the write and the
     read — such monitors NACK writes or corrupt reply frames while recovering
     from other bus traffic (e.g. right after `ddcutil detect`).
3. **ddcci-backlight polish**:
   - brightness reads are served from a cache seeded at probe (a real DDC read
     is ~75 ms and lags behind applied writes, which made GNOME's slider
     bounce on read-back);
   - writes that reverse direction within 200 ms are suppressed from reaching
     the monitor: gnome-shell intermittently fights itself through
     `logind SetBrightness` at slider extremes and on fast drags. Real drags
     are monotonic and pass through unchanged.
4. **Kernel 6.8+ auto-probing workaround** — DRM drivers no longer set
   `I2C_CLASS_DDC`, so a udev rule + `ddcci-attach.service` instantiate the
   driver on buses found by `ddcutil`. Includes `ddcci-report.sh`, a one-shot
   diagnostic bundle good enough for a bug report. See `dist/README-ALT.md`.
5. **Packaging/CI** — ALT RPM spec (`dist/dkms-ddcci.spec`, dkms-based) built
   by both Forgejo Actions (altlinux.space) and GitHub Actions.

## Machine-readable debugging context

[](LLM.md) tells any AI assistant how to collect diagnostics
(), triage known failures, and either file an
issue or fix + PR. Users: review what gets submitted — reports are gated
behind your approval and can be redacted.

## Install (ALT Linux / ALT Atomic) ##

One command, picks the right repo branch and starts everything:

```sh
curl -fsSL https://altlinux.space/toxblh/ddcci-driver-linux/raw/branch/master/dist/install-alt.sh | sudo sh
```

(GitHub mirror: replace the host part with
`https://raw.githubusercontent.com/Toxblh/ddcci-driver-linux/master/dist/install-alt.sh`)

Manual equivalent:

```sh
echo 'rpm https://altlinux.space/api/packages/toxblh/alt/group/sisyphus.repo noarch classic' \
    > /etc/apt/sources.list.d/ddcci-toxblh.list        # sisyphus or p11 group
sudo apm system update && sudo apm system install -y kernel-headers-modules-$(uname -r | cut -d. -f1-2) dkms-ddcci
sudo systemctl enable --now ddcci-attach.service
```

After a major kernel update install matching `kernel-headers-modules-<X.Y>`;
`dkms.service` rebuilds the module on the next boot.

## Original README ##

# ddcci-driver-linux #

A pair of Linux kernel drivers for DDC/CI monitors.

DDC/CI is a control protocol for monitor settings supported by most monitors since about 2005.
It is based on ACCESS.bus (an early USB predecessor).

## ddcci (bus driver) ##

This driver detects DDC/CI devices on DDC I²C busses, identifies them and creates corresponding devices.

As this is a I²C driver it won't be autoloaded and must be manually loaded, for example by putting a line with `ddcci`
in `/etc/modules`.

### sysfs interface ###

Each detected DDC/CI device gets a directory in `/sys/bus/ddcci/devices`.

The main device on a bus is named `ddcci[I²C bus number]`.

Internal dependent devices are named `ddcci[I²C bus number]i[hex address]`

External dependent devices are named `ddcci[I²C bus number]e[hex address]`

There the following files export information about the device:

#### capabilities ####

The full ACCESS.bus capabilities string. It contains the protocol, type and model of the device,
a list of all supported command codes, etc.

See the ACCESS.bus spec for more information.

#### idProt ####

ACCESS.bus protocol supported by the device. Usually "monitor".

#### idType ####

ACCESS.bus device subtype. Usually "LCD" or "CRT".

#### idModel ####

ACCESS.bus device model identifier. Usually a shortened form of the device model name.

#### idVendor ####

ACCESS.bus device vendor identifier. Empty if the Identification command is not supported.

#### idModule ####

ACCESS.bus device module identifier. Empty if the Identification command is not supported.

#### idSerial ####

32 bit device number. A fixed serial number if it's positive, a temporary serial number if negative and zero if the
Identification command is not supported.

#### modalias ####

A combined identifier for driver selection. It has the form `ddcci:<idProt>-<idType>-<idModel>-<idVendor>-<idModule>`.

All non-alphanumeric characters (including whitespace) in the model, vendor or module parts are replaced by
underscores to prevent issues with software like `systemd-udevd`.

### Character device interface ###

For each DDC/CI device a character device in `/dev/bus/ddcci/[I²C bus number]/` is created.

The main device on the bus is named `display`.

Internal dependent devices are named `i[hex address]`

External dependent devices are named `e[hex address]`

These character devices can be used to issue commands to a DDC/CI device more easily than over i2c-dev devices.
They should be opened unbuffered and may be opened with O_EXCL if you want exclusive access.

To send a command just write the command byte and the arguments with a single `write()` operation. The length byte and
checksum are automatically calculated.

To read a response use `read()` with a buffer big enough for the expected answer.

NOTE: The maximum length of a DDC/CI message is 127 bytes.

An Example (in Python):

	with open('/dev/bus/ddcci/3/display', 'r+b', buffering=0) as f:
		# Read contrast
		f.write(bytes([0x01, 0x12]))
		response = f.read(8)
		print("Contrast:", response[6] * 256 + response[7], "/", response[4] * 256 + response[5])

The following error codes are used:

* EAGAIN: there was no response yet or (with O_NONBLOCK) the device was in use by another thread
* EBADMSG: there was a response but the checksum didn't match
* EBUSY: the device is opened exclusively by another thread (on open())
* EINVAL: message too big (on write())
* EIO: generic I/O failure
* EMSGSIZE: the buffer was too small (on read())
* ENOMEM: not enough free memory to allocate buffers (on open())

Lower layers may pass error codes not in this list like ENXIO, so be prepared for that.

## ddcci-backlight (monitor backlight driver) ##

For each monitor that supports accessing the Backlight Level White or the Luminance property, a backlight device of type "raw" named like the corresponding ddcci device is created. You can find them
in `/sys/class/backlight/`.

For convenience a symlink "ddcci_backlight" on the device associated with the display connector in `/sys/class/drm/` to the backlight device is created, as long as the graphics driver allows to make this association.

## Limitations ##

Dependent devices (sub devices using DDC/CI directly wired to the monitor, like Calibration devices, IR remotes, etc.) aren't automatically detected.

You can force detection of internal dependent devices by setting the `autoprobe_addrs` module parameter of ddcci.

You can force detection of external dependent devices by writing "ddcci-dependent [address]" into
/sys/bus/i2c/i2c-?/new_device.

There is no direct synchronization if you manually change the luminance with the buttons on your monitor, as this can
only be realized through polling and some monitors close their OSD every time a DDC/CI command is received.

Monitor hotplugging is not detected. You need to detach/reattach the I²C driver or reload the module.

## Installation ##

Generally, you only need to clone the repository and run make to build both kernel modules, then run make load. To permanently install the drivers, use `make install` (or `make -f Makefile.dkms install` if you prefer DKMS).

## Debugging ##

Both drivers use the [dynamic debugging feature](https://www.kernel.org/doc/html/latest/admin-guide/dynamic-debug-howto.html) of the Linux kernel.

To get detailed debugging messages, set the `dyndbg` module parameter. For details on the syntax and for dynamic activation/deactivation of the debugging messages, see the documentation linked above.

If you want to enable debugging permanently across reboots, create a file `/etc/modprobe.d/ddcci.conf` containing lines like the following before loading the modules:

	options ddcci dyndbg
	options ddcci-backlight dyndbg

## License ##

These kernel modules are free software; you can redistribute them and/or modify them under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.
