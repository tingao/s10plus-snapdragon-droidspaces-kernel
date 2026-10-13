# Thanks

This kernel is mostly other people's work, assembled. The parts that were hard to figure out are
named here, with what each one contributed.

## [ravindu644](https://github.com/ravindu644) / [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)

Droidspaces is what turns the phone into a container host, and its documentation is what told us
which kernel options matter:

* **The cgroup file-prefix patch**: `Documentation/resources/kernel-patches/non-GKI/02.fix_restore
  cgroup file prefix handling .patch`.
  Android mounts cgroup v1 with `noprefix`, so the cpuset files are `cpus`/`mems` while `runc` asks
  for `cpuset.cpus`/`cpuset.mems` and fails with `ENOENT`; without the patch **every `docker run`
  inside a container fails** on a 4.14 kernel, and no combination of runtime flags works around it.
  The fix is entirely theirs.
* **`Documentation/Kernel-Configuration.md`**: the required and recommended option list, and the
  table stating that kernels 4.4 to 4.19 support "Docker inside containers" with systemd older than
  258. Our config was checked against that list item by item.
* The warning that KernelSU's kprobe hooks are not usable below 5.10 is what led to the manual hook
  approach here.

## [sm8150-samsung](https://github.com/sm8150-samsung)

Maintainers of the two trees this is built from:

* [`android_kernel_samsung_sm8150-common`](https://github.com/sm8150-samsung/android_kernel_samsung_sm8150-common)
  (branch `lineage-18.1`), the kernel source. The branch *vintage* matters: a different one is
  either refused by the bootloader or hangs on the logo.
* [`android_device_samsung_beyond2qlte`](https://github.com/sm8150-samsung/android_device_samsung_beyond2qlte),
  the device DTB that goes into `boot.img`.

## [LineageOS](https://lineageos.org/)

The `lineage-18.1` branch is LineageOS's long-term maintenance of this kernel, carried forward
through years of Android releases. Much of what makes this tree boot at all on the device is their
work, and their device trees were the reference for how this hardware is meant to be configured.

## [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) and [weishu](https://github.com/tiann) / [KernelSU](https://github.com/tiann/KernelSU)

KernelSU-Next is a fork of KernelSU by weishu, and this kernel carries its manual-hook mode because
that is what works below 5.10. The version and UAPI pairing between kernel and manager, the thing
that silently reports "Working" while every `su` fails, is their design, and their documentation is
what made it diagnosable.

## [topjohnwu](https://github.com/topjohnwu) / [Magisk](https://github.com/topjohnwu/Magisk)

`magiskboot` is what unpacks the stock Android boot image and repacks it with a different kernel.
The packing script here uses it directly.

## [AOSP](https://source.android.com/) / Google

`avbtool`, from `external/avb`, writes the AVB footer and the verification-disabled `vbmeta` that
lets an unsigned kernel boot.

## The Linux kernel community, Samsung and Qualcomm

4.14.190 is a long-lived stable branch, and underneath it is Samsung's and Qualcomm's code for this
SoC.

## Everyone who documented the dead ends

The failures documented in [SOURCE.md](SOURCE.md) and [FLASHING.md](FLASHING.md) were solved by
strangers who wrote down what happened to them:

* the `bpf_prog_query(BPF_CGROUP_DEVICE) failed: invalid argument` reports that identified the
  cgroup v2 problem as a kernel-version issue rather than a configuration mistake;
* the XDA threads on container kernels for other Snapdragon devices, whose build recipes and config
  fragments were a reference for what a working setup looks like;
* the LineageOS and KernelSU communities, whose answers to "it says Working but `su` does nothing"
  pointed at the hook mode.

If you use this and hit something new, write it down the way the people above did.
