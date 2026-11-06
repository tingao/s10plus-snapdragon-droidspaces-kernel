#!/usr/bin/env bash
# Reproducible build of the SM-G9750 (beyond2qlte / beyond2q) 4.14.190
# KernelSU-Next + Droidspaces kernel baseline, from public sources.
#
#   ./scripts/build.sh                 # full: trees -> config -> build -> publish config
#   ./scripts/build.sh --configure     # stop after publishing artifacts/config-baseline.txt
#   ./scripts/build.sh --no-build      # same as --configure
#   ./scripts/build.sh --clean-config  # discard out/.config and regenerate it
#
# Everything is idempotent: re-running reuses the existing trees/out dir and
# only rebuilds what changed.  Long output goes to logs/build-*.log.
#
# Layout it expects/produces (all relative to the workspace root):
#   kernel/android_kernel_samsung_sm8150-common   kernel tree  (+ KernelSU-Next/ inside it)
#   toolchain/src/clang-r416183b                  Android clang 12.0.5 (r416183b)
#   toolchain/gcc/aarch64-linux-android-4.9       GNU binutils 2.27 (aarch64-linux-android-4.9)
#   toolchain/host-tools/bc                       GNU bc (host has none)
#   patches/                                      01,02 kernel patches, 03 KernelSU backport
#   out/                                          build output (O=), inside the kernel tree
#   artifacts/config-baseline.txt                 the exact built config
#   logs/                                         build logs
set -euo pipefail

WS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KERNEL=${KERNEL:-$WS/kernel/android_kernel_samsung_sm8150-common}
KSU=$KERNEL/KernelSU-Next
OUT=$KERNEL/out
TC=$WS/toolchain
CLANG=$TC/bin/clang
REAL_CLANG=$TC/src/clang-r416183b/bin/clang
CROSS=$TC/gcc/aarch64-linux-android-4.9/bin/aarch64-linux-android-
BUILD_USER=${BUILD_USER:-builder}
BUILD_HOST=${BUILD_HOST:-localhost}
BUILD_TIMESTAMP=${BUILD_TIMESTAMP:-"2026-01-01 00:00:00 UTC"}
JOBS=${JOBS:-$(nproc)}

KERNEL_REPO=https://github.com/sm8150-samsung/android_kernel_samsung_sm8150-common.git
KERNEL_COMMIT=d1d9579baf3fc993b91d8ee22227fbb50464c8b4
KSU_REPO=https://github.com/KernelSU-Next/KernelSU-Next.git
# 9b08e88 = "kernel: sync version code" (2979 commits, tag v3.2.0-legacy).
# KernelSU-Next's kernel/Kbuild computes version = 30000 + commit_count + 150,
# so this commit reports 33129 - the version the phone's v3.1.0 manager expects.
# The one-file 4.14 sched-header backport from its child c49a631 is applied as
# patches/03-ksu-4.14-sched-header-backport.patch (a late upstream history
# re-push made commit c49a631 itself count as 2980 = version 33130).
KSU_COMMIT=9b08e88862000d5c50fb2e43a5b75123cf472e54

DEFCONFIG=beyond2qlte_droidspaces_defconfig
DEFCONFIG_BASE=lineage_beyond2qlte_defconfig
FRAGMENT=$WS/scripts/droidspaces-ksu.fragment

MODE=full
for a in "$@"; do
  case $a in
    --configure|--no-build) MODE=configure ;;
    --clean-config) MODE=clean-config ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

log_i() { printf '\033[1m== %s\033[0m\n' "$*"; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# The DSH harness leaks PYTHONHOME/PYTHONPATH pointing into its AppImage; host
# python3 refuses to start with those set.  Every kernel build recipe on this
# machine must run with them unset.
pymake() { env -u PYTHONHOME -u PYTHONPATH "$@"; }

# ---------------------------------------------------------------- toolchain
log_i "toolchain"
[ -x "$REAL_CLANG" ] || die "clang not found at $REAL_CLANG (expected Android clang r416183b: 12.0.5)"
[ -x "$CROSS"ld ] || die "GNU aarch64-linux-android-ld not found at ${CROSS}ld"
[ -x "$TC/host-tools/bc/bin/bc" ] || die "host bc not found at $TC/host-tools/bc/bin/bc"

# clang wrapper: filters the host's /opt/cuda autodetection line from `clang -v`
# output; see its own header for the full story.
[ -x "$CLANG" ] || die "clang wrapper missing at $CLANG"

export PATH="$TC/host-tools/bc/bin:$TC/src/clang-r416183b/bin:$TC/gcc/aarch64-linux-android-4.9/bin:$PATH"
export LD_LIBRARY_PATH="$TC/src/clang-r416183b/lib64:${LD_LIBRARY_PATH:-}"
export KBUILD_BUILD_USER="$BUILD_USER"
export KBUILD_BUILD_HOST="$BUILD_HOST"
export KBUILD_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"
# Fixed version number: the kernel's ".version" file otherwise increments on
# every make run, which makes two builds of the same source differ (#1/#2/...).
export KBUILD_BUILD_VERSION="${BUILD_VERSION:-1}"

mk() {
  pymake make -j"$JOBS" -C "$KERNEL" O="$OUT" ARCH=arm64 \
    CROSS_COMPILE="$CROSS" REAL_CC="$CLANG" CC="$CLANG" CLANG_TRIPLE=aarch64-linux-gnu- "$@"
}

# ---------------------------------------------------------------- sources
log_i "kernel tree (lineage-18.1 @ $KERNEL_COMMIT)"
if [ ! -d "$KERNEL/.git" ]; then
  mkdir -p "$(dirname "$KERNEL")"
  git clone -b lineage-18.1 --single-branch "$KERNEL_REPO" "$KERNEL"
fi
if ! git -C "$KERNEL" cat-file -e "$KERNEL_COMMIT^{commit}" 2>/dev/null; then
  git -C "$KERNEL" fetch origin lineage-18.1
fi
# Keep the cve-hardening branch if it already exists (it may carry later CVE
# commits); only create it at the baseline commit in a fresh tree.
if git -C "$KERNEL" show-ref --verify --quiet refs/heads/cve-hardening; then
  git -C "$KERNEL" checkout -q cve-hardening
else
  git -C "$KERNEL" checkout -q -B cve-hardening "$KERNEL_COMMIT"
fi
echo "   baseline commit $KERNEL_COMMIT is ancestor of HEAD: $(git -C "$KERNEL" merge-base --is-ancestor "$KERNEL_COMMIT" HEAD && echo yes || echo NO)"
# The phone's baseline reports "4.14.190-gd1d9579ba-dirty", i.e. a 9-character
# short sha.  A modern git on a 6M-object repo defaults to 12; force the same
# schema so our uname string matches the device's.
git -C "$KERNEL" config core.abbrev 9
git -C "$KERNEL" config user.name "${GIT_AUTHOR_NAME:-builder}"
git -C "$KERNEL" config user.email "${GIT_AUTHOR_EMAIL:-builder@localhost}"
echo "   HEAD $(git -C "$KERNEL" rev-parse --short HEAD) branch $(git -C "$KERNEL" branch --show-current)"

log_i "KernelSU-Next (.git preserved; commit count determines reported version)"
if [ ! -d "$KSU/.git" ]; then
  git clone "$KSU_REPO" "$KSU"
fi
if ! git -C "$KSU" cat-file -e "$KSU_COMMIT^{commit}" 2>/dev/null; then
  git -C "$KSU" fetch origin
fi
git -C "$KSU" checkout -q -B baseline-kernel "$KSU_COMMIT"
KSU_COUNT=$(git -C "$KSU" rev-list --count HEAD)
echo "   HEAD $(git -C "$KSU" rev-parse --short HEAD) commits=$KSU_COUNT expected version=$((30000 + KSU_COUNT + 150))"

# ---------------------------------------------------------------- KSU integration
log_i "KernelSU-Next integration (symlink + Kconfig/Makefile lines)"
[ -d "$KSU/kernel" ] || die "$KSU/kernel is missing"
ln -sfn ../KernelSU-Next/kernel "$KERNEL/drivers/kernelsu"
grep -q 'drivers/kernelsu/Kconfig' "$KERNEL/drivers/Kconfig" || \
  printf '\nsource "drivers/kernelsu/Kconfig"\n' >> "$KERNEL/drivers/Kconfig"
grep -q 'kernelsu/' "$KERNEL/drivers/Makefile" || \
  printf 'obj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL/drivers/Makefile"

# ---------------------------------------------------------------- defconfig
log_i "defconfig: $DEFCONFIG = $DEFCONFIG_BASE + droidspaces/KSU fragment"
[ -f "$KERNEL/arch/arm64/configs/$DEFCONFIG_BASE" ] || die "missing $DEFCONFIG_BASE"
cat "$KERNEL/arch/arm64/configs/$DEFCONFIG_BASE" "$FRAGMENT" \
  > "$KERNEL/arch/arm64/configs/$DEFCONFIG"

# ---------------------------------------------------------------- patches
log_i "patches"
KSU_PATCH_APPLIED=0
for p in "$WS"/patches/*.patch; do
  name=$(basename "$p")
  case $name in
    01-*) dir=$KERNEL ;;
    02-*) dir=$KERNEL ;;
    03-*) dir=$KSU; KSU_PATCH_APPLIED=1 ;;
    *)    dir=$KERNEL ;;
  esac
  if patch -d "$dir" -p1 --dry-run --forward --fuzz=3 -s < "$p" >/dev/null 2>&1; then
    patch -d "$dir" -p1 --forward --fuzz=3 -s < "$p"
    echo "   applied $name"
  elif patch -d "$dir" -p1 --dry-run --reverse --fuzz=3 -s < "$p" >/dev/null 2>&1; then
    echo "   already applied $name"
  else
    die "patch $name does not apply (or is already applied differently); inspect $dir"
  fi
done

# ---------------------------------------------------------------- host quirk
# Kernel 4.14's scripts/mkcompile_h generates LINUX_COMPILER as
#   $($CC -v 2>&1 | grep ' version ' ...)
# and this host's Android clang 12.0.5 prints a CUDA autodetection line
# ("Found CUDA installation: /opt/cuda, version 11.0") in -v output because
# /opt/cuda exists.  It matches " version " and makes compile.h a multi-line,
# syntactically broken define, which breaks init/version.c.  Drop that line.
MKCH=$KERNEL/scripts/mkcompile_h
if ! grep -q 'Found CUDA installation' "$MKCH"; then
  env -u PYTHONHOME -u PYTHONPATH python3 - "$MKCH" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "  CC_VERSION=$($CC -v 2>&1 | grep ' version ' | sed 's/[[:space:]]*$//')"
new = ("  # cve-hardening host quirk: this host's Android clang prints a CUDA\n"
       "  # autodetection line in -v output because /opt/cuda exists; it matches\n"
       "  # \" version \" and would corrupt LINUX_COMPILER. Drop that line.\n"
       "  CC_VERSION=$($CC -v 2>&1 | grep ' version ' | grep -v 'Found CUDA installation' | sed 's/[[:space:]]*$//')")
if old in s:
    open(p, 'w').write(s.replace(old, new, 1))
elif 'Found CUDA installation' in s:
    pass
else:
    sys.exit("ERROR: mkcompile_h CC_VERSION line not in expected form")
PY
  echo "   scripts/mkcompile_h: CUDA line filter present"
else
  echo "   scripts/mkcompile_h already patched"
fi

# Tags like baseline-build / cve-* must not suppress or corrupt the -g<sha>
# suffix in the release string (device schema: 4.14.190-g<sha>-dirty).  Later
# upstream kernels filter tags with --match "v[0-9]*"; backport that filter.
SLV=$KERNEL/scripts/setlocalversion
if ! grep -q 'describe --match "v\[0-9\]\*"' "$SLV"; then
  env -u PYTHONHOME -u PYTHONPATH python3 - "$SLV" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
a = 'if [ -z "`git describe --exact-match 2>/dev/null`" ]; then'
b = 'if [ -z "`git describe --exact-match --match "v[0-9]*" 2>/dev/null`" ]; then'
c = 'if atag="`git describe 2>/dev/null`"; then'
d = 'if atag="`git describe --match "v[0-9]*" 2>/dev/null`"; then'
if a in s and c in s:
    open(p, 'w').write(s.replace(a, b, 1).replace(c, d, 1))
    print("   patched scripts/setlocalversion (tag filter)")
PY
else
  echo "   scripts/setlocalversion already patched"
fi

# ---------------------------------------------------------------- configure
if [ "$MODE" = clean-config ]; then rm -f "$OUT/.config"; fi
if [ ! -f "$OUT/.config" ]; then
  log_i "configure ($DEFCONFIG + olddefconfig)"
  mkdir -p "$OUT"
  mk "$DEFCONFIG" > "$WS/logs/config-defconfig.log" 2>&1 || { tail -20 "$WS/logs/config-defconfig.log"; die "defconfig failed"; }
  mk olddefconfig > "$WS/logs/config-olddefconfig.log" 2>&1 || { tail -20 "$WS/logs/config-olddefconfig.log"; die "olddefconfig failed"; }
else
  log_i "configure (reusing existing $OUT/.config; use --clean-config to regenerate)"
fi

# The CVE audit depends on this file existing early: publish it right after
# the config exists, before the long compile.
mkdir -p "$WS/artifacts"
cp "$OUT/.config" "$WS/artifacts/config-baseline.txt"
echo "   published artifacts/config-baseline.txt ($(wc -l < "$WS/artifacts/config-baseline.txt") lines)"
log_i "key config values"
for c in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK CONFIG_USER_NS CONFIG_NET_NS \
         CONFIG_CGROUP_DEVICE CONFIG_DEVTMPFS CONFIG_VETH CONFIG_SYSVIPC \
         CONFIG_SECCOMP CONFIG_OVERLAY_FS CONFIG_BUILD_ARM64_DT_OVERLAY \
         CONFIG_NETFILTER_XT_MATCH_ADDRTYPE CONFIG_IP_NF_TARGET_MASQUERADE \
         CONFIG_SEC_BEYOND2QLTE_PROJECT; do
  printf '   %-32s %s\n' "$c" "$(grep -E "^$c=|^# $c is not set" "$OUT/.config" | head -1)"
done
# Hard assertions: must be built-in, not modules, for the phone's runtime
# (KernelSU + droidspaces/docker: namespaces, cgroups, overlay, veth/bridge,
# netfilter).  NETFILTER_XT_MATCH_ADDRTYPE is required by dockerd's
# `iptables -m addrtype --dst-type LOCAL` inside the container (found live:
# stock Samsung kernel had it, our first baseline build missed it).
for c in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK \
         CONFIG_NETFILTER_XT_MATCH_ADDRTYPE CONFIG_IP_NF_NAT \
         CONFIG_IP_NF_TARGET_MASQUERADE CONFIG_NF_NAT_MASQUERADE_IPV4 \
         CONFIG_NF_NAT_MASQUERADE_IPV6 CONFIG_IP6_NF_TARGET_MASQUERADE \
         CONFIG_BRIDGE_NETFILTER CONFIG_NF_CONNTRACK CONFIG_NETFILTER_XTABLES \
         CONFIG_VETH CONFIG_BRIDGE CONFIG_CGROUP_DEVICE CONFIG_OVERLAY_FS \
         CONFIG_USER_NS CONFIG_NET_NS CONFIG_DEVTMPFS; do
  grep -q "^$c=y" "$OUT/.config" || die "$c is not enabled (=y) in $OUT/.config"
done
# Intentional security divergence from stock: nf_tables stays disabled.
grep -q '^# CONFIG_NF_TABLES is not set' "$OUT/.config" || die "CONFIG_NF_TABLES must stay disabled (security divergence)"
echo "   docker/KSU-critical config assertions: PASS (nf_tables intentionally off)"

[ "$MODE" = configure ] && { echo; echo "configure-only run finished."; exit 0; }

# ---------------------------------------------------------------- KSU source edits
# KernelSU-Next/kernel/Kbuild performs its 4.14 compatibility edits (inject
# path_umount() into fs/namespace.c, declare it in fs/internal.h, patch
# seccomp/selinux/ologk headers) from $(shell ...) at make-parse time.  With a
# parallel build the first parse can happen after fs/namespace.o was already
# compiled, which then fails at vmlinux link with "undefined reference to
# path_umount".  Parse it explicitly first: the edits land in the tree before
# anything that uses them is compiled, deterministically.
log_i "pre-parse KernelSU-Next Kbuild (applies its in-tree source edits)"
mk drivers/kernelsu/ > "$WS/logs/ksu-preparse.log" 2>&1 || {
  tail -30 "$WS/logs/ksu-preparse.log"; die "KernelSU-Next pre-parse build failed"; }
echo "   done (log logs/ksu-preparse.log)"

# ---------------------------------------------------------------- build
log_i "build Image + Image-dtb (-j$JOBS)"
LOG=$WS/logs/build-$(date -u +%Y%m%dT%H%M%SZ).log
START=$(date +%s)
mk Image-dtb > "$LOG" 2>&1 || { tail -40 "$LOG"; die "build failed (log $LOG)"; }
WALL=$(( $(date +%s) - START ))
echo "   wall time: ${WALL}s   log: $LOG"

KSU_VER=$(grep -oE 'KernelSU-Next version: [0-9]+' "$LOG" | awk '{print $3}' | head -1)
echo "   KernelSU-Next version printed by build: ${KSU_VER:-<none>}"
[ "${KSU_VER:-}" = "33129" ] || die "KernelSU-Next version is ${KSU_VER:-missing}, expected 33129"

ls -l "$OUT/arch/arm64/boot/Image" "$OUT/arch/arm64/boot/Image-dtb"
echo "$KSU_VER" > "$WS/logs/ksu-version.txt"
echo
echo "Next: ./scripts/pack-boot.sh   (packs artifacts/AP-boot-beyond2qlte-droidspaces-cve-baseline.tar.md5)"
