#!/bin/sh
# Build the Droidspaces kernel for the Galaxy S10+ (SM-G9750, beyond2qlte).
#
#   ./build-kernel.sh /path/to/toolchain [/path/to/device-tree]
#
# Expects the kernel tree checked out from sm8150-samsung/android_kernel_samsung_sm8150-common
# at branch lineage-18.1, with the KernelSU-Next tree dropped in at its root (see SOURCE.md),
# and run from the root of that tree.
#
# Toolchain paths arrive as arguments or environment variables.
set -eu

TC="${1:-${TOOLCHAIN:-}}"
DT="${2:-${DEVICE_TREE:-}}"
[ -n "$TC" ] || { echo "usage: $0 /path/to/toolchain [/path/to/device-tree]"; exit 2; }

HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${OUT:-$PWD/out}"
DEFCONFIG=beyond2qlte_droidspaces_defconfig

# A neutral identity: the default would bake your username and machine name into the version
# string, which anyone running `uname -a` on the phone can then read.
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-builder}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-localhost}"

# A fixed build date, for the same reason and for reproducibility: without it the kernel carries
# the moment you happened to build it, and two builds of the same tree give different images.
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-2026-01-01 00:00:00 UTC}"

CLANG="$TC/llvm-arm-toolchain-ship/10.0.9/bin/clang"
CROSS="$TC/gcc-cfp/gcc-cfp-single/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
export PATH="$TC/llvm-arm-toolchain-ship/10.0.9/bin:$PATH"
export LD_LIBRARY_PATH="$TC/llvm-arm-toolchain-ship/10.0.9/lib:${LD_LIBRARY_PATH:-}"
[ -x "$CLANG" ] || { echo "clang not found at $CLANG"; exit 2; }

MK="make -j$(nproc) O=$OUT ARCH=arm64 CROSS_COMPILE=$CROSS REAL_CC=$CLANG CC=$CLANG CLANG_TRIPLE=aarch64-linux-gnu-"

echo "=== 1. defconfig ==="
cp arch/arm64/configs/lineage_beyond2qlte_defconfig "arch/arm64/configs/$DEFCONFIG"
cat >> "arch/arm64/configs/$DEFCONFIG" <<'EOF'

# --- What Droidspaces needs (see its Kernel-Configuration documentation) ---
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_NAMESPACES=y
CONFIG_PID_NS=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_SCHED=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_PIDS=y
CONFIG_CGROUP_NET_PRIO=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_MEMCG=y
CONFIG_DEVTMPFS=y
CONFIG_OVERLAY_FS=y
CONFIG_VETH=y
CONFIG_BRIDGE=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TMPFS_XATTR=y
CONFIG_ANDROID_PARANOID_NETWORK=n

# --- KernelSU-Next: manual hooks, because the kprobe hooks are documented as 5.10+ only ---
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_KSU_KPROBES_HOOK is not set
EOF

echo "=== 2. KernelSU-Next integration (symlink + two lines) ==="
[ -d KernelSU-Next ] || { echo "KernelSU-Next/ is missing - see SOURCE.md"; exit 2; }
ln -sfn ../KernelSU-Next/kernel drivers/kernelsu
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || \
  printf '\nsource "drivers/kernelsu/Kconfig"\n' >> drivers/Kconfig
grep -q 'kernelsu/' drivers/Makefile || \
  printf 'obj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile

echo "=== 3. patches ==="
for p in "$HERE"/patches/*.patch; do
  echo "  $p"
  patch -p1 --forward --fuzz=3 < "$p" || echo "    (already applied?)"
done

echo "=== 4. configure ==="
$MK "$DEFCONFIG" >/dev/null
$MK olddefconfig >/dev/null
for c in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK CONFIG_KSU_KPROBES_HOOK \
         CONFIG_USER_NS CONFIG_NET_NS CONFIG_CGROUP_DEVICE CONFIG_DEVTMPFS CONFIG_VETH \
         CONFIG_SYSVIPC CONFIG_SECCOMP CONFIG_OVERLAY_FS; do
  printf '   %-30s %s\n' "$c" "$(grep -E "^$c=|^# $c is not set" "$OUT/.config" | head -1)"
done

echo "=== 5. build ==="
$MK
ls -l "$OUT/arch/arm64/boot/Image"
md5sum "$OUT/arch/arm64/boot/Image"

echo
echo "=== 6. pack an Odin tar (boot.img + vbmeta.img) ==="
if [ -n "$DT" ]; then
  "$HERE/pack-odin.sh" "$OUT" "$DT"
else
  echo "  no device tree given, skipping DTB-dependent packing"
fi

echo
echo "Done. Flash the AP-*.tar.md5 in Odin (see FLASHING.md)."
