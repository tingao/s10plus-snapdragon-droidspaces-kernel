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
| Device tree (DTB) | [sm8150-samsung](https://github.com/sm8150-samsung), `android_device_samsung_beyond2qlte`, branch `lineage-18.1` | GPL-2.0 |
| KernelSU-Next | [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next), a fork of KernelSU by weishu. The project root is GPL-3.0, but the part compiled into a kernel carries its own GPL-2.0 licence at `KernelSU-Next/kernel/LICENSE` | GPL-2.0 (the compiled part) |
| Droidspaces | [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS), for its kernel requirements and one of its non-GKI kernel patches | GPL-3.0, see below |
| `avbtool` usage | Android AVB (AOSP) | Apache-2.0 |

The kernel is distributed under **GPL-2.0**; see [LICENSE](LICENSE) and [COPYING](COPYING). Because
this is a modified GPL work, the complete corresponding source is identified in
[SOURCE.md](SOURCE.md), which gives the upstream tree, branch, defconfig, patch set and toolchain, so
anyone can rebuild the exact binary.

### About the two patches in `build/patches/`

`01-ksu-manual-hooks.patch` was written for this tree and is GPL-2.0, like the kernel it modifies.

`02-cgroup-file-prefix.patch` is **not** ours. It is the Droidspaces project's own non-GKI kernel
patch, `Documentation/resources/kernel-patches/non-GKI/02.fix_restore cgroup file prefix handling
.patch`, from upstream commit `50cb2ccbef7d84852f2600bb4d3e69f6bd736561`. Its authorship is recorded
in the patch header and it is redistributed unmodified apart from re-anchoring the hunk against this
older `kernel/cgroup/cgroup.c`; the change itself is upstream's. Droidspaces is a GPL-3.0 project and
its patches sit under that single repository licence, while this kernel is GPL-2.0-only. In practice
kernel patches are treated as falling under the licence of the kernel file they modify, and this
patch is distributed here as part of a GPL-2.0 kernel, with its origin stated so anyone can follow it
upstream and judge for themselves.

## What the release contains

The release asset `AP-boot-beyond2qlte-droidspaces.tar.md5` is an Odin AP file holding two partitions:

* `boot.img`: the kernel built from the sources above, holding the compressed kernel, the appended
  DTB, and an AVB0 footer.
* `vbmeta.img`: an AVB structure with verification disabled (`flags 3`), required to boot an unsigned
  kernel on this device. This one file is not built here and did not come off the device. It is signed
  with the public AOSP AVB test key (`testkey_rsa4096`, key SHA-1
  `2597c218aae470a130f61162feaae70afd97f011`), and its descriptors and `com.android.build.*` properties
  describe an **SM-G975U** (`beyond2qltesq`) Android 11 build, `G975USQS4FUA1`, which is not this model.
  Its `boot` hash descriptor therefore does not match the `boot.img` above. `flags 3` is what makes that
  harmless: nothing on the device is verified, which is the whole reason an unsigned kernel boots at all.

It deliberately does **not** contain `recovery.img`: only `boot` and `vbmeta` need to change, and the
smaller archive is easier to verify. Keep your own stock firmware (BL/AP/CP/CSC for your model and
CSC) if you want a way back.

## Trademarks and risk

Samsung, Galaxy and S10 are trademarks of Samsung Electronics. This project is not affiliated with,
endorsed by or supported by Samsung, Qualcomm, LineageOS, KernelSU-Next or Droidspaces.

Flashing unofficial software voids warranties and can destroy the device. It permanently trips Knox,
which is unavoidable and expected. Unlocking the bootloader wipes your data. Proceed only on a device
you own and are willing to lose.
