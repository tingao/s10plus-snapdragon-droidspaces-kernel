# How v2.0.0 was verified

Everything below was run on a real SM-G9750 (`beyond2qlte`) with the stock Android 12
`G9750ZHU8HZE1` firmware, unlocked bootloader, KernelSU-Next manager v3.1.0.
No emulator, no “it compiles, ship it”.

## 1. Host-side checks on every image before it goes near the phone

* `boot.img` is exactly **67,108,864 bytes** (the SM-G9750 boot partition size — read from the
  device, not hardcoded from another model).
* The kernel extracted back out of the packed `boot.img` has the **same SHA256 as the built
  `Image`** — catches packing mistakes rather than trusting the build.
* The appended DTB (998,096 bytes) is the genuinely built `sm8150.dtb` + `sm8150-v2.dtb`, and the
  AVB footer is valid (`Algorithm NONE`, `Flags 3`, rollback index 0) so the unlocked bootloader
  accepts an unsigned kernel.
* The Odin tar is POSIX ustar, `boot.img` + `vbmeta.img`, owner/group 0/0, mode 0644, and the
  `.tar.md5` trailer names the same file and hashes the tar body correctly
  (`python3 build/verify-tarmd5.py`).

## 2. Flashing

`boot-cve-hardened-v2.img` was flashed over the boot partition, with the SHA256 verified in three
places: before flashing, read back from the partition on the device, and read back over USB from the
host. Then the phone was rebooted and the boot ID change confirmed.

## 3. Functional matrix (every boot)

Run by `scripts/verify-kernel.sh`-style checks, 26 checks, 0 failures, 1 skip:

| check | result |
|---|---|
| kernel build string `4.14.190-gd913da1ac` | PASS |
| KernelSU version kernel-side = 33129, `su` works | PASS |
| SELinux Permissive | PASS |
| live boot partition SHA256 == flashed image | PASS |
| cgroup v1 cpuset present, both `cpuset.cpus` and `cpus` (Droidspaces/Docker fix) | PASS |
| container `krakow` running, `docker ps` shows Portainer | PASS |
| DNAT: `https://127.0.0.1:9443` and `:9000` → HTTP 200 | PASS |
| `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y`, functional `iptables -m addrtype` | PASS |
| `ip -6 route` inside container, UDP echo inside container | PASS |
| `/proc/net/nf_conntrack` readable | PASS |
| dmesg: kernel panic / oops / internal error / WARNING count = 0 | PASS |
| 30 required kernel config options still enabled | PASS |
| `tc netem` inside container | SKIP — `CONFIG_NET_SCH_NETEM` is not set; same as stock, not a regression |

## 4. Cold-boot campaign

The failure mode we were hunting was **intermittent**, so a single good boot proves nothing. Four
consecutive cold boots, no manual intervention, checking the *previous* boot's console for crash
signatures each time:

| boot | boot ID | boot time | container autostart | Docker/Portainer | previous-boot crash scan |
|---|---|---|---|---|---|
| flash → boot #0 | `496cf3de…` | 51 s | 15 s | up | clean |
| cold B1 | `3d039697…` | 55 s | 21 s | up | clean |
| cold B2 | `a73e2786…` | 54 s | 21 s | up | clean |
| cold B3 | `ededb8a0…` | 61 s | 15 s | up | clean |
| cold B4 | `83627eb6…` | 61 s | 15 s | up | clean |

*Container autostart* means the module log says `Boot Summary: Daemon: Running | 1 started | 0
failed | 0 skipped` and `docker ps` shows Portainer — without anyone starting the container.
*Crash scan* means the previous boot's `/proc/last_kmsg` contained no `Kernel panic`, no
`Software Watchdog`, and none of the KernelSU `on_post_fs_data already done` loop lines.

## 5. Runtime smoke

Inside the container: `docker run --rm alpine ping 1.1.1.1` → 0% packet loss (exercises Docker
networking and the AF_PACKET TX/RX path), UDP echo (send+recv) OK, 200 × `ip route`/`ip -6 route`
(netlink dump/termination path) OK, and a 4-thread × 100,000-iteration `PTHREAD_PRIO_INHERIT`
mutex stress (PI-futex path, `CVE-2021-3347`) OK. Post-test dmesg: 0 faults.

## 6. The v1 failure, for the record

The first build (`f4e308b2…`) passed everything above except cold boot #2 of 4: init spun in
`task_work_run → on_post_fs_data_cbfun`, printing `KernelSU: on_post_fs_data already done` 23,424
times in ~2 s, and the software watchdog panicked the phone 600 s after the last pet.

Cause: KernelSU-Next used a non-atomic `bool first_zygote` checked-then-cleared; two concurrent
zygote `app_process -Xzygote` execs could both queue the **same static** `callback_head`, and a
callback queued twice is self-linked (`cb->next == cb`), so `task_work_run()` never terminates.

Fix: claim registration with `atomic_cmpxchg`, cancel any still-pending copy before queueing,
and check `task_work_add()`'s return. KSU's git history is untouched, so the reported version stays
**33129**. v1 was never published; v2 passes the exact boot where v1 failed, plus one more.

## 7. What this verification does not prove

* Long-term stability (we ran ~15 minutes of runtime smoke and 4 cold boots, not days).
* We did not fuzz the kernel, and no exploit was executed against these fixes.
* Android userspace/ROM is untouched: the stock firmware's security patch level stays 2023-02-01.
* Subsystems that only run rarely on this device (some drivers, unusual filesystems) were exercised
  only insofar as the functional matrix reaches them.

## 8. Droidspaces runtime update (v6.6.0 → v7.1.0)

The kernel release was validated together with the current Droidspaces runtime, because a kernel is
only useful if the container stack on top of it still works.

* Upstream: `ravindu644/Droidspaces-OSS` v7.1.0 (release `4344dc5`, 2026-10-27).
  APK versionName `7.1.0` / versionCode `71001518`; `droidspaces` binary 478,376 B (SHA256
  `9ac190cd…`), built 2026-10-27.
* Update performed **in place** over the existing v6.6.0 runtime (APK installed with `-r`, new binary
  pushed to `/data/local/Droidspaces/bin/` with the `u:object_r:droidspacesd_exec:s0` context,
  module files replaced, reboot). Existing container `krakow` (Debian 13 + Docker + Portainer) and
  its `container.config` were **byte-identical after the update** — no migration.
* File-level diff: `post-fs-data.sh` and `service.sh` byte-identical; `module.prop` version bumped;
  `sepolicy.rule` +6 lines (hwservicemanager binder transfer + `anland` rules); busybox unchanged.

| boot | boot ID | boot time | container autostart | Docker/Portainer | previous-boot crash scan | matrix |
|---|---|---|---|---|---|---|
| update reboot | `db94771b…` | 61 s | 6 s | up | clean | PASS 28/0/1 |
| cold #1 | `4d50c332…` | 54 s | 21 s | up | clean | PASS 28/0/1 |
| cold #2 | `36cb9908…` | 54 s | 21 s | up | clean | PASS 28/0/1 |

The 28-check matrix additionally asserts that the module, the APK and the running binary all report
v7.1.0. DNAT on 9443/9000 still returns HTTP 200, and the kernel's boot partition SHA256 is unchanged
(`f532bd0e…`) — the runtime update does not touch the kernel.

Rollback to v6.6.0 is prepared and dry-run tested (reinstall the old APK, restore the old binary and
module files with their original contexts, reboot). Kernel-side nothing changes, so rollback is
independent of the kernel release.
