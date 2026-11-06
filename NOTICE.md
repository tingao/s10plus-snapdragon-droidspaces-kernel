# Notice and attribution

This repository packages a **Linux kernel built from GPL sources** plus the configuration that makes
it useful with Droidspaces and KernelSU-Next. No Samsung proprietary code is included and no Samsung
binaries are modified: the kernel is compiled from published GPL sources, and the release archive
contains a `boot.img` **built from those sources** plus a verification-disabled `vbmeta`, which is
what an unsigned kernel needs to boot on this device.

## Components

| Component | Author / project | Licence |
|---|---|---|
| Kernel source | [sm8150-samsung](https://github.com/sm8150-samsung), `android_kernel_samsung_sm8150-common`, branch `lineage-18.1`. Ultimately Samsung and Qualcomm code with LineageOS and Linux stable work on top | GPL-2.0 |
| Device tree (DTB) | [sm8150-samsung](https://github.com/sm8150-samsung), `android_device_samsung_beyond2qlte`, branch `lineage-18.1`. Note: that repository contains no DTS files; the shipped DTB is built from the kernel tree's own `arch/arm64/boot/dts/qcom/` sources | GPL-2.0 |
| KernelSU-Next | [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next), a fork of KernelSU by weishu. The project root is GPL-3.0, but the part compiled into a kernel carries its own GPL-2.0 licence at `KernelSU-Next/kernel/LICENSE` | GPL-2.0 (the compiled part) |
| Droidspaces | [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS), for its kernel requirements and one of its non-GKI kernel patches | GPL-3.0, see below |
| `avbtool` usage | Android AVB (AOSP) | Apache-2.0 |

The kernel is distributed under **GPL-2.0**; see [LICENSE](LICENSE) and [COPYING](COPYING). Because
this is a modified GPL work, the complete corresponding source is identified in
[SOURCE.md](SOURCE.md), which gives the upstream tree, branch, defconfig, patch set and toolchain, so
anyone can rebuild the exact binary.

### About the patches in `build/`

`build/patches/01-ksu-manual-hooks.patch` was written for this tree and is GPL-2.0, like the kernel
it modifies.

`build/patches/02-cgroup-file-prefix.patch` is **not** ours. It is the Droidspaces project's own
non-GKI kernel patch, `Documentation/resources/kernel-patches/non-GKI/02.fix_restore cgroup file
prefix handling .patch`, from upstream commit `50cb2ccbef7d84852f2600bb4d3e69f6bd736561`. Its
authorship is recorded in the patch header and it is redistributed unmodified apart from re-anchoring
the hunk against this older `kernel/cgroup/cgroup.c`; the change itself is upstream's. Droidspaces is
a GPL-3.0 project and its patches sit under that single repository licence, while this kernel is
GPL-2.0-only. In practice kernel patches are treated as falling under the licence of the kernel file
they modify, and this patch is distributed here as part of a GPL-2.0 kernel, with its origin stated so
anyone can follow it upstream and judge for themselves.

`build/patches/03-ksu-4.14-sched-header-backport.patch` is a narrow 4.14 compatibility fix taken from
KernelSU-Next's own history (the child commit of the pinned revision) and applied to the KernelSU-Next
checkout only.

`build/patches/04-ksu-post-fs-data-task-work-atomic.patch` was written for this release: it makes
KernelSU-Next's `post-fs-data` task_work registration atomic to fix an intermittent boot panic. It is
GPL-2.0, like the KernelSU-Next kernel code it modifies.

`build/cve-series/` contains 41 kernel patches equal to upstream Linux stable commits (or documented
4.14 adaptations of them), each carrying its upstream CVE/fix SHA in the commit message. They are
GPL-2.0, like the kernel.

## What the release contains

The release asset `AP-boot-beyond2qlte-droidspaces-cve-hardened-v2.tar.md5` is an Odin AP file holding
two partitions:

* `boot.img`: the kernel built from the sources above, holding the compressed kernel, the appended
  DTB, and an AVB0 footer. Exactly 67,108,864 bytes — the SM-G9750 boot partition size.
* `vbmeta.img`: an AVB structure with verification disabled (`flags 3`), required to boot an unsigned
  kernel on this device. This one file is not built here and did not come off the device in a
  recoverable way: it is a copy of the verification-disabled vbmeta already present on the test phone
  (which came from the earlier v1.0.0 release workflow). It is signed with the public AOSP AVB test
  key (`testkey_rsa4096`, key SHA-1 `2597c218aae470a130f61162feaae70afd97f011`), and its descriptors
  and `com.android.build.*` properties describe an **SM-G975U** (`beyond2qltesq`) Android 11 build,
  `G975USQS4FUA1`, which is not this model. Its `boot` hash descriptor therefore does not match the
  `boot.img` above. `flags 3` is what makes that harmless: nothing on the device is verified, which is
  the whole reason an unsigned kernel boots at all.

The rollback asset `AP-stock-rollback-beyond2qlte.tar.md5` holds the stock `boot.img` the phone ran
before this project (SHA256 `1b0eb367…c3b5`) plus the same vbmeta, and is meant to be flashed the same
way.

The `boot-cve-hardened-v2.img` asset is the raw 64 MiB boot partition image for `dd` flashing (for a
phone that already boots and is rooted).

The release deliberately does **not** contain `recovery.img`: only `boot` and `vbmeta` need to change,
and the smaller archive is easier to verify. Keep your own stock firmware (BL/AP/CP/CSC for your model
and CSC) if you want a complete way back.

## Trademarks and risk

Samsung, Galaxy and S10 are trademarks of Samsung Electronics. This project is not affiliated with,
endorsed by or supported by Samsung, Qualcomm, LineageOS, KernelSU-Next or Droidspaces.

Flashing unofficial software voids warranties and can destroy the device. It permanently trips Knox,
which is unavoidable and expected. Unlocking the bootloader wipes your data. Proceed only on a device
you own and are willing to lose.
