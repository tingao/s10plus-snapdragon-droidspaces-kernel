# How this kernel is built

Reproducible from public sources. Nothing here is patched in a binary-only way.

Two builds live in this repository's history: **v1.0.0** (2026-10-13, no CVE fixes) and
**v2.0.0-cve-hardening** (2026-11-06, 35 CVE fixes, the current release). This document describes
v2; the v1 recipe is still in `build/build-kernel.sh`/`build/pack-odin.sh` and in git history.

## Sources

| | |
|---|---|
| Kernel | [`sm8150-samsung/android_kernel_samsung_sm8150-common`](https://github.com/sm8150-samsung/android_kernel_samsung_sm8150-common), branch **`lineage-18.1`**, commit `d1d9579baf3fc993b91d8ee22227fbb50464c8b4` (Linux 4.14.190) |
| KernelSU-Next | [`KernelSU-Next/KernelSU-Next`](https://github.com/KernelSU-Next/KernelSU-Next), tag `v3.2.0-legacy`, commit `9b08e88862000d5c50fb2e43a5b75123cf472e54` |
| Droidspaces | [`ravindu644/Droidspaces-OSS`](https://github.com/ravindu644/Droidspaces-OSS) — its documentation, its required config, and the cgroup `noprefix` kernel patch |
| CVE fixes | upstream Linux stable (gregkh/linux) and openela/kernel-lts `linux-4.14.y`; see `build/cve-series/` |
| Device tree | the DTB is built **from the kernel tree itself** (`arch/arm64/boot/dts/qcom/sm8150.dtb` + `sm8150-v2.dtb`, concatenated by the `Image-dtb` target). The `sm8150-samsung/android_device_samsung_beyond2qlte` repo contains no DTS files and is not on the build path |

The tree has to be the one whose last commit predates the phone's own kernel build date. A different
vintage either gets refused by the bootloader or hangs on the logo. Samsung's own 4.14.190 tree and a
4.14.117 source were both tried and both failed.

## What differs from the stock tree

1. **KernelSU-Next in manual-hook mode.** Its own Kconfig says of the kprobe hooks: *"This should not
   be used on kernel below 5.10."* On 4.14 the manager reports *Working* and lists grants while every
   `su` still fails. The manual hook set is the six call sites: `drivers/input/input.c`, `fs/exec.c`,
   `fs/open.c`, `fs/read_write.c`, `fs/stat.c`, `kernel/reboot.c`.
   See `build/patches/01-ksu-manual-hooks.patch`.
2. **The Droidspaces cgroup patch.** See `build/patches/02-cgroup-file-prefix.patch`. Without it Docker
   cannot start a container: Android mounts cgroup v1 with `noprefix`, so the cpuset files are `cpus`
   and `mems` while `runc` asks for `cpuset.cpus`/`cpuset.mems`. The patch makes `cgroup_add_file()`
   publish the controller-prefixed name as a link as well. This is the upstream Droidspaces
   `02.fix_restore cgroup file prefix handling.patch`, adapted to 4.14 `kernel/cgroup/cgroup.c`.
3. **KernelSU 4.14 `sched/types.h` backport.** `build/patches/03-ksu-4.14-sched-header-backport.patch`.
   Applied **uncommitted** inside the KernelSU-Next checkout, because committing it would change the
   KSU tree's commit count and therefore the reported version (see below).
4. **KernelSU `task_work` boot-race fix.**
   `build/patches/04-ksu-post-fs-data-task-work-atomic.patch`. KernelSU-Next registered its
   `post-fs-data` callback through a non-atomic `bool first_zygote`, so two concurrent zygote execs
   could `task_work_add()` the same *static* `callback_head` twice. A callback queued twice is
   self-linked (`cb->next == cb`) and `task_work_run()` never terminates: init spins, and the software
   watchdog panics the phone ~600 s later. Observed once in four boots on the would-be release; fixed
   with an atomic claim + defensive `task_work_cancel`. Also uncommitted in the KSU checkout for the
   same versioning reason.
5. **The CVE series.** 41 patches applied in order on top of the baseline:
   `build/cve-series/0001-…` … `0041-…` (and `combined.diff`). Each commit message records the CVE,
   the mainline fix SHA and the 4.14.y backport SHA where one exists. The list of CVEs and how they
   were selected is in [CVE-LIST.md](../CVE-LIST.md).
6. **A defconfig fragment** (`build/config-fragment.txt`): namespaces, cgroup controllers, seccomp,
   devtmpfs, veth, bridge, overlayfs, user namespaces, SysV IPC, KernelSU manual hooks, plus
   `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y` (docker's iptables NAT; the stock Samsung kernel had it,
   LineageOS's defconfig did not) and `CONFIG_NF_NAT_MASQUERADE_IPV6=y` +
   `CONFIG_IP6_NF_TARGET_MASQUERADE=y` (stock parity). `CONFIG_NF_TABLES` is deliberately left **off**
   — it removes the whole nf_tables CVE class.

## Toolchain

```
clang        Android (7284624, based on r416183b) clang version 12.0.5
             LineageOS prebuilt android_prebuilts_clang_kernel_linux-x86_clang-r416183b, branch lineage-20.0
GNU ld       (binutils-2.27-44492f8e) 2.27.0.20170315  from AOSP aarch64-linux-android-4.9
bc           GNU bc 1.08.2 (build host had none)
```

Use **GNU ld**. `ld.lld` fails on this 4.14 tree with
`output file too large: 18446743524132959040 bytes`.

The v1.0.0 notes named Samsung's `llvm-arm-toolchain-ship/10.0.9`; that prebuilt is not published in
any public repository we could find, so the v2 build uses the publicly available clang 12.0.5 above.
It builds this tree cleanly and produces a booting kernel (verified on-device, 4/4 cold boots).

Two host quirks are handled by the scripts (they cost us hours, so they are documented):

* the clang wrapper filters the host's `/opt/cuda` autodetection line out of `clang -v`; otherwise
  kernel 4.14's `scripts/mkcompile_h` corrupts `include/generated/compile.h` and the build dies in
  `init/version.c`;
* kernel scripts must run with `PYTHONHOME`/`PYTHONPATH` unset if your shell has them set by a
  snap/flatpak-style runtime (`ModuleNotFoundError: No module named 'encodings'`).

## Workspace layout and build

```sh
# layout expected by build/v2/build.sh
workspace/
  kernel/android_kernel_samsung_sm8150-common/   # kernel tree + KernelSU-Next/ inside it
  toolchain/src/clang-r416183b/                  # clang 12.0.5
  toolchain/gcc/aarch64-linux-android-4.9/       # GNU binutils
  toolchain/host-tools/bc/bin/bc                 # GNU bc
  toolchain/bin/clang                            # wrapper (filters `clang -v` noise)
  scripts/build.sh                               # from this repo: build/v2/build.sh
  scripts/pack-boot.sh                           # from this repo: build/v2/pack-boot.sh
```

```sh
# 1. kernel tree
git clone https://github.com/sm8150-samsung/android_kernel_samsung_sm8150-common.git
cd android_kernel_samsung_sm8150-common && git checkout d1d9579baf3f

# 2. KernelSU-Next inside it
git clone https://github.com/KernelSU-Next/KernelSU-Next.git
cd KernelSU-Next && git checkout 9b08e88862000d5c50fb2e43a5b75123cf472e54 && cd ..
ln -sfn ../KernelSU-Next/kernel drivers/kernelsu
echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig
echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile

# 3. KernelSU patch 03 (uncommitted on purpose)
patch -p1 -d KernelSU-Next < ../build/patches/03-ksu-4.14-sched-header-backport.patch

# 4. baseline kernel patches
patch -p1 < ../build/patches/01-ksu-manual-hooks.patch
patch -p1 < ../build/patches/02-cgroup-file-prefix.patch

# 5. config + build (the script copies the defconfig, appends
#    build/config-fragment.txt, applies the remaining edits, builds Image-dtb)
../scripts/build.sh            # or: bash ../build/v2/build.sh

# 6. KernelSU patch 04 (uncommitted on purpose) and rebuild
patch -p1 -d KernelSU-Next < ../build/patches/04-ksu-post-fs-data-task-work-atomic.patch
../scripts/build.sh

# 7. apply the CVE series and rebuild
git am ../build/cve-series/0*.patch
../scripts/build.sh

# 8. pack the Odin tar + dd image
../scripts/pack-boot.sh
```

The scripts set the variables that would otherwise record the build machine in the kernel's version
string: `KBUILD_BUILD_USER=builder`, `KBUILD_BUILD_HOST=localhost`,
`KBUILD_BUILD_TIMESTAMP="2026-01-01 00:00:00 UTC"` and, importantly,
`KBUILD_BUILD_VERSION=1` — without the last one every `make` increments the `#N` build counter and
produces a different Image for identical sources. Override any of them to name your own machine.

Build times on a 32-core host: cold full build ~125 s, warm incremental ~90 s (the Samsung FIPS hook
re-hashes `vmlinux` on every link), single-object compile 2–8 s.

## KernelSU-Next integration

```
KernelSU-Next/                     # the tree, at 9b08e888 (tag v3.2.0-legacy)
drivers/kernelsu -> ../KernelSU-Next/kernel
drivers/Kconfig   : source "drivers/kernelsu/Kconfig"
drivers/Makefile  : obj-$(CONFIG_KSU) += kernelsu/
```

The released kernel reports KernelSU-Next version **33129**, the number the v3.1.0 manager accepts.
Nothing sets that value by hand: KernelSU-Next's `kernel/Kbuild` computes it as
`30000 + <commit count of the KernelSU-Next tree> + 150`. That is also why patches 03 and 04 are
applied to the working tree **without committing**: a commit would bump the count to 2980 and report
33130, which the v3.1.0 manager does not accept. Read the `-- KernelSU-Next version:` line the build
prints and pair the manager to whatever it says.

## Packing

`build/v2/pack-boot.sh` produces both the Odin AP tar and the raw boot image:

* `boot.img` is the Samsung-format image: kernel (gzip), the built DTB appended, AVB0 footer;
  exactly **67,108,864 bytes** (the SM-G9750 boot partition size, read from the device — do not
  hardcode a size from another S10 variant).
* the AVB footer is `Algorithm NONE`, `Flags 3` (verification and hashtree disabled), rollback index
  0 — that is what lets an unsigned kernel boot on the unlocked bootloader.
* the Odin file is a POSIX **ustar** archive containing `boot.img` + `vbmeta.img` (owner/group 0/0,
  mode 0644) followed by `<md5 of the tar>  <tar name>\n`. The name inside the trailer **must** equal
  the file name, or Odin refuses the file.
* the script asserts, and aborts on: wrong boot.img size, kernel extracted from the packed image with
  a different SHA256 than the built `Image`, empty/changed DTB, and a wrong trailer.

Inputs it needs from a real device of the same model: a stock boot image to use as the header
template and a verification-disabled `vbmeta.img` (both are captured from the phone before flashing;
the release tar contains the copy from ours).

## Verifying a build

Host side:

```sh
sha256sum out/arch/arm64/boot/Image
magiskboot unpack boot.img && sha256sum kernel        # == Image
avbtool info_image --image boot.img                    # Algorithm NONE, Flags 3
python3 build/verify-tarmd5.py AP-*.tar.md5            # VERDICT : ODIN WILL ACCEPT THIS
```

Device side (this is the matrix used for the release; see [docs/VERIFICATION.md](../docs/VERIFICATION.md)):

```sh
zcat /proc/config.gz | grep -E '^CONFIG_(KSU|KSU_MANUAL_HOOK|NETFILTER_XT_MATCH_ADDRTYPE|NF_NAT_MASQUERADE_IPV6|IP6_NF_TARGET_MASQUERADE)='
ls /sys/fs/cgroup/cpuset/cpuset.cpus /sys/fs/cgroup/cpuset/cpus   # both names = Docker fix
docker run --rm alpine echo ok                                     # inside a Droidspaces container
adb shell "su -c 'sha256sum /dev/block/by-name/boot'"              # == flashed image sha256
```

## Two things about the version string

`uname -a` on the released kernel reports:

```
Linux version 4.14.190-gd913da1ac #1 SMP PREEMPT 2026-01-01 00:00:00 UTC
```

* The `-g<sha>` suffix is the kernel tree's `localversion` from `setlocalversion`; `gd913da1ac` is
  the integration commit of our public build. Your own build will show your commit instead.
* **`(builder@localhost)`** and the fixed date are deliberate: the version string is visible to
  anyone who runs `uname -a` on the phone, so it was neutralised. If you build without setting those
  variables, yours will contain your own username/hostname.
* A different `O=` directory changes the Image because `CONFIG_DEBUG_INFO` embeds the build path.
  That is expected; compare builds made in the same-named out dir.

The kernel can carry source *paths* from `__FILE__` (for example in `arch/arm64/kernel/entry.S`).
The released `boot.img` stores the kernel compressed, so those paths do not show up in `strings` of
the archive, but decompressing the kernel section recovers them. Check yours with:
`strings out/arch/arm64/boot/Image | grep -E '^/(home|root|Users)/'`
