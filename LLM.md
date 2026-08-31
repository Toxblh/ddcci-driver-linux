# LLM.md — context for AI assistants debugging ddcci on a user's machine

You are helping a user whose external-monitor brightness / ddcci setup is
broken. Follow this file. Two outcomes are acceptable:

1. **Report**: collect a diagnostic report, get explicit user approval, help
   the user file it as a GitHub issue.
2. **Fix**: find the bug, rebuild the module locally, verify, then send a PR.

Never invent a third outcome (e.g. silently patching a user's system and
walking away without a report or upstream fix).

## What this project is

Fork of the ddcci kernel drivers (original upstream deleted; based on
tastelessjolt 0.4.5) packaged as the ALT RPM `dkms-ddcci`. Two modules:

- `ddcci` — DDC/CI bus driver, attaches to i2c buses at address 0x37;
- `ddcci-backlight` — exposes monitor luminance as `/sys/class/backlight/ddcciN`.

Kernel 6.8+ dropped DDC auto-probing (`I2C_CLASS_DDC`), so a udev rule +
`ddcci-attach.service` find DDC buses via `ddcutil detect` and instantiate
the driver. The package ships `/usr/sbin/ddcci-report.sh` (diagnostics) and
`dist/install-alt.sh` (installer).

**Main repo:** https://github.com/Toxblh/ddcci-driver-linux (issues + PRs here).
**Mirror (read-only):** https://altlinux.space/toxblh/ddcci-driver-linux —
packages in its registry, do not send PRs there.

## Code map (if you end up fixing)

- `ddcci/ddcci.c` — probe = `ddcci_identify_device` + `ddcci_get_caps`.
  Contains deliberate quirks: the single `0x00` byte write before identify
  (resets monitor DDC FIFO) and retry loops around write+read. Do NOT
  "simplify" them away — Dell U2725QE and other USB-C monitors fail without.
- `ddcci-backlight/ddcci-backlight.c` — brightness read cache (DDC read is
  ~75 ms and lags applied writes) and <200 ms write-reversal suppression
  (gnome-shell fights itself through logind SetBrightness). Do NOT remove.
- `dkms-ddcci.spec` — ALT gear spec at repo root; `dist/` — service, udev
  rule, report/install scripts.
- `ci/gh-local.sh`, `ci/gear-local.sh` — local CI reproducers (podman);
  they pack the tree via `git archive HEAD` — commit first, then run.

## Step 1 — collect diagnostics

```
sudo /usr/sbin/ddcci-report.sh            # full
sudo /usr/sbin/ddcci-report.sh --redact   # masks hostname + serials
```

Writes `/tmp/ddci-report-*.txt` (`/tmp/ddcci-report-*.txt`): system info,
dkms state, sysfs, `ddcutil environment`, and a live hex trace of a
re-probe with dynamic debug enabled.

**PRIVACY GATE (mandatory):** the report contains the hostname, monitor
model and serial numbers, kernel logs. Show the report (or at least list
what it contains) to the user and get an explicit "yes, send this" before
any submission. Prefer `--redact` unless the maintainers ask for full data.

## Step 2 — quick triage table

| Symptom | Cause | Fix |
|---|---|---|
| `modprobe: module not found` after kernel update | headers/module not built | `sudo apm system install -y kernel-headers-modules-$(uname -r | cut -d. -f1-2)` then `sudo dkms install ddcci/0.4.5 --force`; `dkms.service` does this on boot |
| journal: `no DDC device on bus N` | nothing DDC-capable there | run `ddcutil detect`; if empty, monitor/cable issue, not the driver |
| dmesg: `core device [6e] probe failed: -19` | corrupted identify/caps | run `ddcci-report.sh`, attach; check retry logic still present |
| dmesg: `probe failed: -17` / `duplicate filename` | zombie ddcci kobject pins the bus-device name after a reconnect storm | since 0.4.5-alt3 `ddcci-attach.service` self-heals (retries, then module reset); manually: `sudo modprobe -r ddcci-backlight ddcci`, delete stale `0x37` client, restart the service |
| slider bounces / brightness flickers | read-cache or reversal suppression regressed | inspect `ddcci-backlight.c`, hex trace shows alternating writes |
| both sliders drive the external monitor / internal slider gone | GNOME/mutter backlight-mapping bug on device churn (sysfs is fine) | Settings - Displays - turn the external monitor off, Apply, on, Apply; relogin also works; upstream: https://gitlab.gnome.org/GNOME/mutter/-/issues/5016 |
| `/sys/class/backlight/ddcci13` missing after boot | service didn't run / no udev trigger | `systemctl status ddcci-attach.service`, `journalctl -u ddcci-attach` |

For deeper tracing (module must be loaded):

```
echo 'module ddcci +p'        | sudo tee /sys/kernel/debug/dynamic_debug/control
echo 'module ddcci_backlight +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
```

**Gotcha:** dynamic-debug flags reset when the module reloads — re-enable
after every rebuild.

## Step 3a — file the issue

GitHub issues require the *user's* account; you cannot submit anonymously.
Your job: prepare everything. Draft the issue (title = one-line symptom,
body = what happened + what you tried + full report pasted as a code block
or attached), show it to the user, let them review the redacted report and
submit at:

    https://github.com/Toxblh/ddcci-driver-linux/issues/new

## Step 3b — fix and PR

```
git clone https://github.com/Toxblh/ddcci-driver-linux && cd ddcci-driver-linux
# edit code; then rebuild on the user's machine:
sudo dkms remove ddcci/0.4.5 --all ||:
sudo rsync -a --delete ./ /usr/src/ddcci-0.4.5/   # keep dkms tree in sync
sudo dkms add -m ddcci -v 0.4.5 ||:
sudo dkms install -m ddcci -v 0.4.5 --force
sudo modprobe -r ddcci-backlight ddcci; sudo systemctl start ddcci-attach.service
# verify: ls /sys/class/backlight/ ; reproduce the original bug
```

Before pushing:

- `./ci/gh-local.sh` and `./ci/gear-local.sh` must pass (commit first!).
- If the spec changelog changed: author must be `Builder <hasherc-ci@altlinux.org>`
  and ASCII only — the ALT CI enforces both (em-dashes fail `check-printable`).
- Push to a branch on GitHub, open a PR against `master`, include the
  `ddcci-report.sh` trace that motivated the change.

## Hard rules

1. Never submit any user data anywhere without showing it to the user first.
2. Never remove the retry/quirk/cache logic described above without a
   reproducing trace proving it unnecessary.
3. Never push to master directly; PRs only, CI must be green.
