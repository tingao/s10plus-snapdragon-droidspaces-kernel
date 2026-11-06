# CVE-hardened Droidspaces kernel for the Galaxy S10+ (SM-G9750, beyond2qlte)

A ready-to-flash kernel for the Snapdragon Galaxy S10+ that has what
[Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) needs to run a Linux container, with
KernelSU root, with Docker working inside that container — **and with 35 Linux kernel CVE fixes
backported on top of the stock 4.14.190 base.**

A phone with a broken screen can still run a Debian server you reach over SSH. You do not have to
build anything: download the release, flash it with Odin, install one app.

> **Current release: `v2.0.0-cve-hardening`** (2026-11-06).
> Verified on a real SM-G9750: functional matrix 26/26 PASS and **four consecutive cold boots
> clean** (container and Docker autostart with no intervention each time). See
> [CHANGELOG.md](CHANGELOG.md), [CVE-LIST.md](CVE-LIST.md) and [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Which phone this is for

Samsung Galaxy S10+ 5G with the Snapdragon chip: model SM-G9750, codename `beyond2qlte`, the
China/Hong Kong variant, which its bootloader calls `BEYOND2Q CHNHK`. It also turns up written as
G9750, S10 Plus, or S10+ SD855.

Do not flash this on any other S10:

| Phone | Codename | Why not |
|---|---|---|
| Galaxy S10+ Exynos | `beyond2`, `beyond2lte` | Different SoC |
| Galaxy S10+ US Snapdragon (SM-G975U) | `beyond2q`, `beyond2qltesq` | Different board |
| Galaxy S10, S10e, S10 5G | `beyond0`, `beyond1`, `beyondx` | Different devices |

The device tree here is built for `beyond2qlte`, so a wrong-model flash either refuses to boot or
stops on the Samsung logo. Check the model number on the phone under Settings, About phone before
you start. It has to say SM-G9750.

## Download

Everything is on the [Releases page](https://github.com/tingao/s10plus-snapdragon-droidspaces-kernel/releases).

| Asset | Use it for | Size | SHA256 |
|---|---|---|---|
| `AP-boot-beyond2qlte-droidspaces-cve-hardened-v2.tar.md5` | **Odin / Windows** — boot-only AP tar | 67,184,726 | `1e1807f519e6d59caa6a7be72e6e31714d02229bd5a54e59f4f31203369bb3d5` |
| `boot-cve-hardened-v2.img` | **Linux / rooted phone** — `dd` flash image (exact 64 MiB boot partition content) | 67,108,864 | `f532bd0e7e356ec6b0af9e366b9f8237496434008fd25a8be5f3a7ba4bad0a8a` |
| `AP-stock-rollback-beyond2qlte.tar.md5` | **Rollback** — the stock boot the phone shipped with | 67,184,708 | `954de8f498e775319dd342db6a1696416ab41b2942f953a4c0504c3e85ee5801` |
| `SHA256SUMS` | check any download | — | — |
| `cve-hardening-v2-source.tar.zst` | every patch, config and build script used for v2 | 155,945 | `140e395628c152112222f541993b51aa20e22424976e968b37f9e8b489992387` |

Check what you downloaded — a truncated AP file is the most common reason Odin refuses one:

```sh
sha256sum -c SHA256SUMS            # for the release assets
python3 build/verify-tarmd5.py AP-boot-beyond2qlte-droidspaces-cve-hardened-v2.tar.md5
# ... VERDICT : ODIN WILL ACCEPT THIS
```

Kernel build string after flashing: **`4.14.190-gd913da1ac`**
(`uname -a` → `Linux localhost 4.14.190-gd913da1ac #1 SMP PREEMPT 2026-01-01 00:00:00 UTC aarch64`).

## What you need

* The phone, with Developer options enabled and OEM unlocking switched on.
* **Stock Android 12** on the phone. `G9750ZHU8HZE1` is the version this kernel was built and
  tested against; other stock Android 12 builds for the SM-G9750 will very likely work, but you are
  on your own there.
* Windows with [Odin](https://odindownload.com/) and the Samsung USB drivers (Odin 3.14.1 tested) —
  or a Linux box with `adb` and a rooted phone (see “Linux / already rooted” below).
* The [KernelSU-Next **v3.1.0**](https://github.com/KernelSU-Next/KernelSU-Next/releases) manager
  and [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS/releases).
  **Droidspaces v7.1.0** (release `4344dc5`) is the runtime this release was tested with; v6.6.0
  works too, and upgrading in place from v6.6.0 to v7.1.0 over a running container needs no config
  migration (verified).

Install manager **v3.1.0**, not the newest release. This kernel reports KernelSU version **33129**,
and the manager has to match that version and the UAPI. A newer manager reports the kernel as
unsupported, or complains that the UAPI does not match, which is the most common way to get stuck.

## Quick start: Odin (Windows)

1. Download `AP-boot-beyond2qlte-droidspaces-cve-hardened-v2.tar.md5` and verify its SHA256 above.
2. Unlock the bootloader if you have not: OEM unlocking in Developer options, power off, hold
   **Volume Down + Bixby** and plug the USB cable, long-press **Volume Up**. The phone wipes itself;
   that is expected.
3. Enter Download Mode (power off, **Volume Down + Bixby**, plug in, press **Volume Up** once) and
   read the small text top-left:
   * `KG STATE : Checking` — if it says `Prenormal`, boot Android, run Settings → Software update →
     Download and install (it may say already up to date; the check itself clears it), then retry.
   * `OEM LOCK : OFF` — if it says `ON (U)`, toggle OEM unlocking off/on in Developer options first.
4. In Odin load the `.tar.md5` in the **AP** slot only. Leave BL, CP, CSC empty. Options: tick
   *Auto Reboot* and *F.Reset Time*, nothing else. **Never** Nand Erase or Re-Partition.
5. Press **Start** and wait for `PASS!`. The phone reboots on its own; do not unplug before
   `All threads completed`.

`FLASHING.md` has the slow, screenshot-level version of this, including the Odin logs of a good and
a bad flash and what each failure means. `docs/RECOVERY.md` covers what to do if the phone ever
stops booting (it did not happen during our testing — 4/4 cold boots clean — but plan for it).

## Quick start: Linux / already rooted (no Odin)

If the phone is already rooted with KernelSU and USB debugging enabled, you can flash the boot
partition directly. This is what we used for testing:

```sh
# the image must be exactly 67,108,864 bytes and match the SHA256 above
sha256sum boot-cve-hardened-v2.img

adb push boot-cve-hardened-v2.img /data/local/tmp/boot.img
adb shell "su -c 'dd if=/data/local/tmp/boot.img of=/dev/block/by-name/boot bs=4M conv=fsync'"
# read it back and compare — never skip this
adb shell "su -c 'sha256sum /dev/block/by-name/boot'"
adb reboot
```

More detail, plus the Download-Mode fallback tools (heimdall and the official Samsung `odin4` for
Linux), in [docs/RECOVERY.md](docs/RECOVERY.md). One rule matters: **one protocol action per
Download-Mode entry, and the bootloader answers the ODIN/LOKE handshake only once per USB
connection** — so do not probe first and flash second in the same session.

## Check it worked

With USB debugging on and the phone booted:

```sh
adb shell uname -a
# Linux localhost 4.14.190-gd913da1ac #1 SMP PREEMPT 2026-01-01 00:00:00 UTC aarch64

adb shell /system/bin/su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0

adb shell /system/bin/su -c "zcat /proc/config.gz | grep -E '^CONFIG_(KSU|KSU_MANUAL_HOOK|NETFILTER_XT_MATCH_ADDRTYPE)='"
# CONFIG_KSU=y
# CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
```

If `uname -a` still shows the old build date, the flash did not take — re-check the two bootloader
gates in `FLASHING.md`.

## Root

Install the KernelSU-Next v3.1.0 manager and open it. It should report `Working`,
`Kernel: 4.14.190`, and `Hook mode: Manual`.

Then grant root where you need it: open the manager, go to Superuser, and allow Shell and
Droidspaces. Root does not work until you tap allow. When you test it from a shell, use the full
path, because `which su` does not find it:

```sh
/system/bin/su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0
```

## Droidspaces and Docker inside the container

Install the Droidspaces app, open it, and run Settings → Requirements → Check Requirements.
Everything under “must have” should pass; this kernel has the options it asks for
(`CONFIG_NAMESPACES`, `PID_NS`, `UTS_NS`, `IPC_NS`, `NET_NS`, `SECCOMP(_FILTER)`, `DEVTMPFS`,
`CGROUPS`, `CGROUP_DEVICE`, `VETH`, `BRIDGE`, `OVERLAY_FS`, `USER_NS`, `SYSVIPC`, `POSIX_MQUEUE`,
`MEMCG`).

**Tested runtime: Droidspaces v7.1.0** (release `4344dc5`, APK versionCode `71001518`, binary built
2026-10-27) — verified on this kernel with an existing container (`krakow`, Debian 13 + Docker +
Portainer): 3/3 boots clean, container autostarted, Docker and Portainer up, no config migration.
The previous runtime, v6.6.0, also works. If you are coming from v6.6.0, the update is: install the
new APK over the old one (`adb install -r`), copy the new `droidspaces` binary into
`/data/local/Droidspaces/bin/` (keep `.daemon_mode=1`, keep the `u:object_r:droidspacesd_exec:s0`
context on it), replace the files in `/data/adb/modules/droidspaces/`, reboot. `service.sh` and
`post-fs-data.sh` are byte-identical between those versions; `sepolicy.rule` gains a few binder/`anland`
rules and the container config is unchanged.

Create a container from one of the app's Debian or Ubuntu templates, give it a few GB, and start it.

Docker inside the container needs cgroup v1 (this kernel is 4.14; the cgroup v2 `bpf_prog_query`
path needs a newer kernel) and the `runc` runtime. `crun` fails on Samsung's `schedtune` controller.
Both are container settings, not kernel settings. This kernel also carries the Droidspaces cgroup
noprefix fix, so both names exist inside the container:

```sh
$ cat /sys/fs/cgroup/cpuset/cpuset.cpus
0-7
$ cat /sys/fs/cgroup/cpuset/cpus
0-7
```

Then `docker run --rm alpine echo ok` works.

## What is hardened in v2 (35 CVEs)

The kernel is the stock LineageOS 18.1 4.14.190 tree for `beyond2qlte` with **35 upstream CVE fixes
backported**, chosen by an audit of this exact tree and this exact device config — not a generic
“bump the version” patch dump. Highlights:

* **29 container→host local-privilege/escape fixes** — the realistic attack surface here, because
  the Droidspaces container runs with near-full capabilities: `CVE-2021-22555` (xtables compat heap
  OOB write), `CVE-2020-14386` (AF_PACKET `tpacket_rcv` overflow), `CVE-2022-29581`/`CVE-2023-3776`
  (net/sched UAFs), `CVE-2022-48911` (nf_queue UAF), `CVE-2022-0492` (cgroup v1 release_agent
  escalation), `CVE-2021-3347` (PI-futex UAF), `CVE-2021-47103` (sk_rx_dst RCU), `CVE-2022-42896`
  (Bluetooth L2CAP), `CVE-2020-29661` (tty TIOCSPGRP), and more.
* **2 LAN-remote and 1 adjacent-remote fixes** — crafted packets are the secondary surface: the
  kernel runs with `panic_on_oops=1`, so an oops is a host-wide DoS.
* **AF_PACKET/netlink hardening** (`CVE-2026-80841` TX_RING UAF deferred free, `CVE-2024-56606`,
  `CVE-2024-53140`) — deliberately using the minimal netlink variant that does not break Droidspaces
  container autostart.
* **Filesystem fixes** — `CVE-2024-41012`/`-41020` (fcntl/close locks), `CVE-2024-42304`/
  `-47701` (ext4).

The full list with classes and areas is in [CVE-LIST.md](CVE-LIST.md); the audit that produced it —
including what was deliberately **not** patched — is in
[`cve-hardening-v2-source.tar.zst` → `audit/TARGET-LIST.md`](CVE-LIST.md#residual-risk).

Two config changes ride along, both required for a working phone:

* `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y` — dockerd's iptables NAT setup needs it; the stock Samsung
  kernel had it, the LineageOS defconfig did not. Without it Docker cannot start inside the
  container.
* `CONFIG_NF_NAT_MASQUERADE_IPV6=y` + `CONFIG_IP6_NF_TARGET_MASQUERADE=y` — restored stock parity
  for IPv6 NAT.

Deliberately **not** enabled: `CONFIG_NF_TABLES`. Leaving nf_tables out removes a whole CVE class
from this kernel (intentional divergence from the stock Samsung config).

**v2 also fixes a boot race found during verification**: KernelSU-Next registered its
`post-fs-data` task_work callback with a non-atomic guard, so two concurrent zygote execs could
queue the same static callback twice, self-link it, and spin init until the software watchdog
panicked the phone (observed 1 in 4 boots on v1). The fix — atomic claim + defensive
`task_work_cancel` — is in `build/patches/04-ksu-post-fs-data-task-work-atomic.patch`. v1 was never
published; v2 passed the exact boot where v1 failed, plus one more (4/4 cold boots clean).

**Honest scope:** this hardens the *kernel*. The Android userspace stays whatever your stock ROM is
(SPL 2023-02-01 on `G9750ZHU8HZE1`); kernel patches do not fix userspace CVEs. The audit also found
hundreds of further vulnerable code paths that are not patched here — the kernel is frozen at
4.14.190 upstream, and the ranked list of what remains is documented in the source bundle.

## Recovery and rollback

* **Rollback**: flash `AP-stock-rollback-beyond2qlte.tar.md5` in Odin's AP slot, or `dd`
  `boot-current-stock` back. This is the exact stock boot image your phone shipped with (its SHA256
  is in the table above).
* **No boot / stuck on logo**: enter Download Mode and flash the rollback tar. The phone is
  A-only (no slots), bootloader unlocked, vbmeta verification disabled — a boot-only flash cannot
  touch your data.
* **Linux users**: [docs/RECOVERY.md](docs/RECOVERY.md) has the complete runbook, including the
  heimdall single-action rule, the official Samsung `odin4` Linux binary, the `cdc_acm` caveat and
  the exact commands.
* Keep your own stock firmware (`BL`/`AP`/`CP`/`CSC`) around as the last-resort recovery.

## Build it yourself

[SOURCE.md](SOURCE.md) documents the exact toolchain (Android clang 12.0.5 `r416183b` + GNU
binutils 2.27 — `ld.lld` does not work on this tree), the KernelSU-Next revision pinning, the config
fragment, the four baseline patches and the 41-patch CVE series, plus how to reproduce and verify
the image byte-for-byte. Everything is also in `cve-hardening-v2-source.tar.zst`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). The previous release, `v1.0.0`, is untouched and still available;
it has no CVE fixes.

## Safety

Flashing a boot image on a phone with an unlocked bootloader is reversible — the rollback image and
the stock firmware route are above — but it is still your phone. Read `FLASHING.md` before you
start, never flash a different model, and keep the cable plugged in until Odin says
`All threads completed`. Neither the kernel authors nor the projects it is built from are
responsible if you brick your device.

## Credits

Most of this is other people's work. [CREDITS.md](CREDITS.md) names each project and what it
contributed — in particular the Droidspaces author, whose cgroup patch is the reason Docker works
here, and the Linux kernel community, whose stable backports make the CVE list possible.
