# Changelog

## v2.0.0-cve-hardening — 2026-11-06

First CVE-hardened release. Kernel: `4.14.190-gd913da1ac`.

### Added

* **35 backported Linux kernel CVE fixes** on top of the stock LineageOS 18.1 4.14.190 tree, chosen
  by an audit of this exact tree and this exact device config, not by version bumping:
  29 container-to-host local-privilege/escape fixes, 2 LAN-remote, 2 local-LPE, 1 adjacent-remote.
  Full list: [CVE-LIST.md](CVE-LIST.md). Patch series: `build/cve-series/` (41 patches +
  `combined.diff`), also shipped as release asset `cve-hardening-v2-source.tar.zst`.
* **KernelSU-Next boot-race fix**: `post-fs-data` task_work registration is now claimed atomically
  (`atomic_cmpxchg`) with a defensive `task_work_cancel`, instead of a non-atomic `bool`. This
  prevents a double `task_work_add()` of the same static callback, which self-links `cb->next`,
  spins init and panics the phone via the software watchdog. Patch:
  `build/patches/04-ksu-post-fs-data-task-work-atomic.patch`.
* `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y` — dockerd's iptables NAT setup needs it. The stock Samsung
  kernel shipped it; the LineageOS defconfig did not, which silently broke Docker inside the
  container on the rebuilt kernel.
* `CONFIG_NF_NAT_MASQUERADE_IPV6=y` and `CONFIG_IP6_NF_TARGET_MASQUERADE=y` — restored stock
  parity for IPv6 NAT.
* Release assets: hardened AP tar (Odin), exact `dd` boot image, stock rollback AP tar, SHA256SUMS,
  complete source bundle (patches, config, audit, build scripts).

### Changed

* `CONFIG_NF_TABLES` remains **disabled** (it was enabled in the stock Samsung config). This
  deliberately removes the entire nf_tables CVE class from the kernel.

### Fixed (during verification of the would-be v2)

* v1 of this release (`f4e308b2…`, never published) passed the functional matrix but **panicked on
  one of four boots** because of the KernelSU `task_work` race above. Root-caused from
  `/proc/last_kmsg`, fixed, rebuilt as v2, and re-verified: **4 consecutive cold boots clean**, with
  container and Docker autostarting on every boot. Evidence and the full story:
  [docs/VERIFICATION.md](docs/VERIFICATION.md).

## v1.0.0 — 2026-10-13

Initial release: KernelSU-Next root + Droidspaces + working Docker inside the container on the
SM-G9750, stock LineageOS 18.1 4.14.190 kernel. No CVE fixes. Still available on the Releases page.
