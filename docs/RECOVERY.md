# Recovery runbook (SM-G9750)

You should not need this — the published image passed four consecutive cold boots and a full
functional matrix — but a boot image flash is the one operation on a phone that can leave it
unbootable, so here is the complete route back. Everything below was actually exercised on a real
SM-G9750 during the v2 development, including the failure cases.

**The good news:** the boot partition is the only thing a boot-only flash touches, the bootloader is
unlocked, vbmeta verification is disabled (`Flags 3`), the phone is A-only (no slots), and your data
is on other partitions. A broken boot image is recoverable. Your data is not at risk from these
operations.

## What the phone looks like when it is broken

* Stuck on the Samsung logo, or a boot loop: the flashed kernel is not booting.
* Black screen: hold **Power** ~10–20 s to force a power cycle.
* `Downloading... Do not turn off target!!` on screen: the phone is already in Download Mode — good,
  go flash the rollback.

## Entering and leaving Download Mode

Enter: power the phone off, hold **Volume Down + Bixby**, plug in the USB cable, then press
**Volume Up** once. The screen shows small text top-left (`ODIN MODE`, `PRODUCT NAME: SM-G9750`, …).

Leave without flashing: long-press **Power + Volume Down** for ~10 s. The phone reboots normally.
(A Download Mode entry cannot be exited over USB; there is no reboot command in heimdall's CLI.)

## First choice: Windows + Odin (simplest)

1. Download `AP-stock-rollback-beyond2qlte.tar.md5` from the Releases page and verify its SHA256.
2. Enter Download Mode (above). Check `KG STATE : Checking` and `OEM LOCK : OFF`.
3. Odin → AP slot → the rollback tar → Start. The phone reboots to stock on its own.

This restores the exact stock boot image, i.e. the phone as it was before our kernel.

## Linux: heimdall (no Windows needed)

Use the grimler fork (it resets the USB device before the protocol handshake; the upstream build
works too but needs that reset on many hosts). Build it from source, or use a distro package
(`heimdall` in Arch/CachyOS, `heimdall-flash` in Debian/Ubuntu).

**The one rule that matters:** this Samsung bootloader answers the `ODIN`/`LOKE` handshake **exactly
once per USB connection**, and a read-only action consumes it just like a flash does. So:

* **One protocol action per fresh Download-Mode entry.** Do not run `print-pit` and then `flash` in
  the same session — the second command will fail with the misleading
  `ERROR: Failed to send handshake!`.
* After a failed action, do not retry in a loop: the bootloader's protocol thread stays wedged and
  needs a **phone reboot** (not just a cable replug) to recover.

Read-only check (diagnostics, in its own session):

```sh
heimdall detect
heimdall print-pit --no-reboot      # prints the PIT; leaves the session used up
```

Flashing (fresh Download-Mode entry, single action). heimdall does not unpack Samsung tars, so
extract `boot.img` from the release AP tar first (`tar xf AP-stock-rollback-beyond2qlte.tar.md5
boot.img`) — or use the `boot-current-stock-*.img` from the release source bundle — then:

```sh
heimdall detect
heimdall flash --BOOT boot-current-stock-20261106.img          # auto-reboots when done
```

If that reports `Failed to send handshake`: the session is already consumed. Reboot the phone
(Power + Volume Down ~10 s), re-enter Download Mode, and run **only** the flash command.

### The `cdc_acm` caveat

When the phone is in Download Mode it enumerates as a CDC ACM modem (`04e8:685d`). On most systems
that is fine, but if the kernel's `cdc_acm` driver has bound the interface and is probing the serial
port, it can eat the single handshake. heimdall detaches the kernel driver before claiming the
interface, so it works anyway. Some other tools do not; official Odin's own help says
*"you maybe need to unload a module cdc_acm before downloading"*. If a tool opens the device but
never gets the handshake, try `sudo rmmod cdc_acm` before re-entering Download Mode.

## Linux: official Samsung odin4

Samsung also ships a Linux `odin4` (the same tool as Windows Odin, leaked; widely mirrored). It does
PIT retrieval + MD5 validation + flashing **in a single session**, which sidesteps the
one-handshake rule. Example (AP-only, boot+vbmeta, auto-reboot):

```sh
odin4 --help
odin4 -a AP-stock-rollback-beyond2qlte.tar.md5 -d /dev/bus/usb/002/012 --reboot
```

Get the USB path from `lsusb` (`04e8:685d`) or `odin4 -l`. Caveats we hit on this exact
host/phone: point it at the Download-Mode device explicitly (`-d`), do not run it while the phone is
booted in Android (it may try to talk to the MTP interface), and expect the open-source
reimplementation `Llucs/odin4` (a different project from Samsung's binary) to fail the handshake on
this device/host combination — that is a tool bug, not a phone problem. If a flash is rejected
mid-way, reboot the phone before trying again.

## Linux: `dd` from a rooted phone (what we use for normal updates)

When the phone still boots, this is the fastest and most controlled route — and it is what the
project's own verification uses:

```sh
# 1. verify the image first
sha256sum boot-cve-hardened-v2.img        # must be 67,108,864 bytes and match the release SHA256

# 2. push and write
adb push boot-cve-hardened-v2.img /data/local/tmp/boot.img
adb shell "su -c 'dd if=/data/local/tmp/boot.img of=/dev/block/by-name/boot bs=4M conv=fsync'"

# 3. read back from the partition and compare — never skip this
adb shell "su -c 'sha256sum /dev/block/by-name/boot'"

# 4. reboot
adb reboot
```

The scripts used by the project (`scripts/flash-boot.sh`, `scripts/verify-kernel.sh`) are included in
the source bundle and do exactly this with guards.

## Last resort

Flash your phone's own stock firmware in Odin: `BL` → BL, `AP` → AP, `CP` → CP, `CSC` → CSC (use
`CSC`, not `HOME_CSC`, if you want a clean wipe). For an SM-G9750, download the `G9750ZHU8HZE1`
(or newer) firmware for your CSC from a reputable firmware site before you start flashing anything —
it is the one recovery path that cannot fail because of a bad kernel. It does not depend on our
release at all.

## After recovery

Once Android boots again, re-verify what you have:

```sh
adb shell uname -a                # stock: 4.14.190-gd1d9579ba-dirty; hardened: 4.14.190-gd913da1ac
adb shell "su -c 'cat /data/adb/modules/droidspaces/module.prop'"   # droidspaces version
adb shell "su -c 'ls /sys/fs/cgroup/cpuset/'"                       # cgroup setup
```

If you were mid-update of Droidspaces too, its rollback is independent of the kernel: reinstall the
old APK (`adb install -r Droidspaces-universal-v6.6.0-cff50fa.apk`), restore the old module
directory and binaries, and reboot. The release source bundle lists the exact asset names and hashes.
