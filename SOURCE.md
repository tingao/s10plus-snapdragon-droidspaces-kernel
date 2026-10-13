# How this kernel is built

Reproducible from public sources. Nothing here is patched in a binary-only way.

## Sources

| | |
|---|---|
| Kernel | [`sm8150-samsung/android_kernel_samsung_sm8150-common`](https://github.com/sm8150-samsung/android_kernel_samsung_sm8150-common), branch **`lineage-18.1`** (Linux 4.14.190) |
| Device tree | [`sm8150-samsung/android_device_samsung_beyond2qlte`](https://github.com/sm8150-samsung/android_device_samsung_beyond2qlte), branch `lineage-18.1`, used for the DTB |
| KernelSU-Next | [`KernelSU-Next/KernelSU-Next`](https://github.com/KernelSU-Next/KernelSU-Next), tag **`v3.2.0`**, pinned commit `c49a6316c556f84b8e21ef3af3e1b49032b47ea0` |
| Droidspaces | [`ravindu644/Droidspaces-OSS`](https://github.com/ravindu644/Droidspaces-OSS), for its documentation, its requirements and one of its kernel patches |

The tree has to be the one whose last commit predates the phone's own kernel build date. A different
vintage either gets refused by the bootloader or hangs on the logo. Samsung's own 4.14.190 tree and a
4.14.117 source were both tried and both failed.

## What differs from the stock tree

1. **KernelSU-Next in manual-hook mode.** Its own Kconfig says of the kprobe hooks: *"This should not
   be used on kernel below 5.10."* On 4.14 the manager reports *Working* and lists grants while every
   `su` still fails. The manual hook set is the six call sites the working sibling device uses:
   `drivers/input/input.c`, `fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`,
   `kernel/reboot.c`. See `build/patches/01-ksu-manual-hooks.patch`.
2. **The Droidspaces cgroup patch.** See `build/patches/02-cgroup-file-prefix.patch` and the README.
   Without it Docker cannot start a container. This is the upstream
   `02.fix_restore cgroup file prefix handling.patch`, adapted because the upstream patch is written
   against a newer `kernel/cgroup/cgroup.c`.
3. **A Droidspaces defconfig fragment**: namespaces, cgroup controllers, seccomp, devtmpfs, veth,
   bridge, overlayfs, user namespaces, SysV IPC.

## Toolchain

```
LLVM/clang 10.0.9   (prebuilts/toolchain/llvm-arm-toolchain-ship/10.0.9)
GNU ld 2.25         (gcc-cfp-single/aarch64-linux-android-4.9/bin/aarch64-linux-android-ld)
```

Use GNU ld. `ld.lld` fails on this tree with
`output file too large: 18446743524132959040 bytes`.

## Build

```sh
cd <kernel tree>
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=localhost
../build/build-kernel.sh /path/to/toolchain
```

The script copies `lineage_beyond2qlte_defconfig`, appends the Droidspaces fragment and the KernelSU
manual-hook options, applies the patches, builds, and packs an Odin-flashable `boot.img`.

Set `KBUILD_BUILD_USER` and `KBUILD_BUILD_HOST` if you care what the kernel's version string says.
By default it will contain your own username and machine name, and that string is visible to anyone
who runs `uname -a` on the phone.

## KernelSU-Next integration

The whole KernelSU-Next tree sits at the kernel root, with a symlink and two lines of Kconfig/Makefile:

```
KernelSU-Next/                     # the tree
drivers/kernelsu -> ../KernelSU-Next/kernel
drivers/Kconfig   : source "drivers/kernelsu/Kconfig"
drivers/Makefile  : obj-$(CONFIG_KSU) += kernelsu/
```

`KSU_VERSION_FALLBACK` is set to **33129** so the built kernel reports a version the v3.1.0 manager
accepts. If you change it, you must change the manager to match.

## Packing

`build/pack-odin.sh` builds an Odin tar containing `boot.img` and `vbmeta.img` plus the `.tar.md5`
trailer. Two details are easy to get wrong:

* the name in the trailer must equal the file name (**trap 3** in FLASHING.md);
* `boot.img` here is a Samsung-format image: the kernel, the DTB (from the device tree, appended),
  and an AVB0 footer. `recovery.img` is not part of the release.

## Verifying a build

```sh
zcat /proc/config.gz | grep -E '^CONFIG_(KSU|KSU_MANUAL_HOOK|USER_NS|CGROUP_DEVICE|NET_NS|VETH)='
ls /sys/fs/cgroup/cpuset/cpuset.cpus     # must exist; this is the Docker fix
docker run --rm alpine echo ok           # inside a Droidspaces container, with cgroup v1 forced
```

## Two things about the version string

`uname -a` on the released kernel reports something like:

```
Linux version 4.14.190-g2c5caf3ac-dirty (builder@localhost) #1 SMP PREEMPT Thu Jan 1 00:00:00 UTC 2026
```

* **`-dirty`** is expected and harmless. It means the source tree has local changes on top of the
  upstream commit, here the patches described above. A released image is not built from a pristine
  tree.
* **`(builder@localhost)`** is deliberate. `KBUILD_BUILD_USER` and `KBUILD_BUILD_HOST` were set to a
  neutral value so the version string does not name the machine the kernel was built on. If you build
  it yourself without setting those, yours will contain your own username and hostname, and anyone
  who runs `uname -a` on the phone will see them.

The kernel can carry source *paths* from `__FILE__`, for example in `arch/arm64/kernel/entry.S`. The
released `boot.img` stores the kernel compressed, so those paths do not show up in `strings` output
from the archive, but decompressing the kernel section recovers them. A directory name you would
rather not publish can hide in a release that way. Check the decompressed image:
`strings out/arch/arm64/boot/Image | grep -E '^/(home|root|Users)/'`
