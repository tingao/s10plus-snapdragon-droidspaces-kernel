#!/usr/bin/env bash
# Pack a built kernel into an Odin-flashable AP tar.md5 for SM-G9750
# (beyond2qlte): Samsung-format 64 MiB boot.img + verification-disabled vbmeta.
#
#   ./scripts/pack-boot.sh
#
# Inputs:
#   out/arch/arm64/boot/Image        kernel Image
#   out/arch/arm64/boot/Image-dtb    Image + appended DTB (Samsung "UNCOMPRESSED_IMG" container)
#   device/boot-current-stock-*.img  template for the Samsung boot header (kernel format, cmdline, offsets)
#   device/vbmeta-current.img        verification-disabled AVB metadata (copied as-is)
#   toolchain/host-tools/magiskboot  Magisk boot image unpacker/repacker
#   avbtool                          AOSP AVB footer tool (system package)
#
# Output:
#   artifacts/AP-boot-beyond2qlte-droidspaces-cve-baseline.tar.md5   (boot.img + vbmeta.img)
#   variants of the above for later CVE builds via OUTPUT_NAME=...
#
# Verification performed: boot.img is exactly 67108864 bytes, has a valid AVB
# footer, its header says the kernel was repacked from Image, and the kernel
# extracted back out of the final boot.img has the same sha256 as Image.
set -euo pipefail

WS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KERNEL=${KERNEL:-$WS/kernel/android_kernel_samsung_sm8150-common}
# OUT_DIR lets patchers pack a build from their private build dir, e.g.
#   OUT_DIR=$WS/patch-out/cve-net OUTPUT_NAME=AP-boot-...-cve-net ./scripts/pack-boot.sh
OUT=${OUT_DIR:-$KERNEL/out}
TC=$WS/toolchain

MAGISKBOOT=${MAGISKBOOT:-$TC/host-tools/magiskboot}
AVBTOOL=${AVBTOOL:-/usr/bin/avbtool}
TEMPLATE=${TEMPLATE:-$WS/device/boot-current-stock-20261106.img}
VBMETA=${VBMETA:-$WS/device/vbmeta-current.img}
PARTITION_SIZE=67108864
NAME=${OUTPUT_NAME:-AP-boot-beyond2qlte-droidspaces-cve-baseline}
W=${PACK_WORK:-$WS/out/pack}

IMAGE=$OUT/arch/arm64/boot/Image
IMAGE_DTB=$OUT/arch/arm64/boot/Image-dtb
ARTIFACTS=$WS/artifacts

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
py()  { env -u PYTHONHOME -u PYTHONPATH python3 "$@"; }

for f in "$IMAGE" "$IMAGE_DTB" "$MAGISKBOOT" "$AVBTOOL" "$TEMPLATE" "$VBMETA"; do
  [ -e "$f" ] || die "missing input: $f"
done
[ -x "$MAGISKBOOT" ] || die "$MAGISKBOOT is not executable"
mkdir -p "$ARTIFACTS"

rm -rf "$W"; mkdir -p "$W"
cp "$TEMPLATE" "$W/boot.img"
cp "$AVBTOOL" "$W/avbtool.py"
(cd "$W" && "$MAGISKBOOT" unpack boot.img > unpack.log 2>&1) || \
  die "magiskboot unpack failed (see $W/unpack.log)"
[ -f "$W/kernel" ] || die "magiskboot unpack produced no kernel"
echo "   template: kernel $(stat -c%s "$W/kernel" 2>/dev/null || echo ?) bytes, dtb $(stat -c%s "$W/kernel_dtb" 2>/dev/null || echo 0) bytes"

cp "$IMAGE" "$W/kernel"
py - "$IMAGE" "$IMAGE_DTB" "$W/kernel_dtb" <<'PY'
import sys
img = open(sys.argv[1], 'rb').read()
idt = open(sys.argv[2], 'rb').read()
if idt[:16] != b'UNCOMPRESSED_IMG':
    sys.exit("unexpected Image-dtb header: %r" % idt[:16])
if idt[20:20 + len(img)] != img:
    sys.exit("Image not found at offset 20 of Image-dtb")
dtb = idt[20 + len(img):]
if not dtb:
    sys.exit("Image-dtb carries an empty DTB - the base sm8150 DTB was not built")
open(sys.argv[3], 'wb').write(dtb)
print("   Image %d bytes, appended DTB %d bytes" % (len(img), len(dtb)))
PY

(cd "$W" && "$MAGISKBOOT" repack boot.img repacked.img > repack.log 2>&1) || \
  die "magiskboot repack failed (see $W/repack.log)"

# Trim the repacked image to the end of the last boot section (drop the old AVB
# footer/slack), then let avbtool pad to the full partition size with flags 3.
py - "$W/repacked.img" "$W/pre-avb.img" <<'PY'
import struct, sys
b = open(sys.argv[1], 'rb').read()
(ksz, _ka, rsz, _ra, ssz, _sa, _ta, pg, _hv, _os) = struct.unpack('<10I', b[8:48])
end = pg + ((ksz + pg - 1) // pg) * pg + ((rsz + pg - 1) // pg) * pg + ((ssz + pg - 1) // pg) * pg
open(sys.argv[2], 'wb').write(b[:end])
print("   boot sections end at %d bytes" % end)
PY

py "$W/avbtool.py" add_hash_footer --image "$W/pre-avb.img" \
  --partition_name boot --partition_size "$PARTITION_SIZE" \
  --flags 3 --algorithm NONE --rollback_index 0
mv "$W/pre-avb.img" "$W/boot.img"
cp "$VBMETA" "$W/vbmeta.img"

BOOT_SIZE=$(stat -c%s "$W/boot.img")
[ "$BOOT_SIZE" = "$PARTITION_SIZE" ] || die "boot.img is $BOOT_SIZE bytes, expected $PARTITION_SIZE"

# Odin rejects a .tar.md5 whose trailer names a different file than the tarball,
# so NAME must be identical in the tar name and the trailer line.
(cd "$W" && chmod 0644 boot.img vbmeta.img && \
  tar --format=ustar --owner=0 --group=0 --numeric-owner -cf "$NAME.tar" boot.img vbmeta.img && \
  cat "$NAME.tar" > "$NAME.tar.md5" && \
  printf '%s  %s\n' "$(md5sum "$NAME.tar" | awk '{print $1}')" "$NAME.tar" >> "$NAME.tar.md5")
cp "$W/$NAME.tar.md5" "$ARTIFACTS/$NAME.tar.md5"

# Optional: also publish the exact boot.img member under a friendly name for the
# plan-A dd path, e.g. BOOT_COPY=$WS/artifacts/boot-cve-hardened.img
if [ -n "${BOOT_COPY:-}" ]; then
  cp "$W/boot.img" "$BOOT_COPY"
  echo "   boot copy     : $BOOT_COPY ($(sha256sum "$BOOT_COPY" | awk '{print $1}'))"
fi

# Strict trailer assertion: the last line of the .tar.md5 must name the same
# tarball and carry that tarball's md5 (Odin rejects anything else).
# (the .tar.md5 is binary tar data followed by one plaintext line, so parse the
# last match of the trailer pattern instead of relying on line tools)
TRAILER=$(tail -c 512 "$ARTIFACTS/$NAME.tar.md5" | grep -a -oE '[0-9a-f]{32}  [^[:space:]]+\.tar' | tail -n 1)
[ -n "$TRAILER" ] || die "no md5 trailer found at end of $ARTIFACTS/$NAME.tar.md5"
TRAILER_MD5=${TRAILER%% *}
TRAILER_NAME=${TRAILER##* }
[ "$TRAILER_NAME" = "$NAME.tar" ] || die "tar.md5 trailer names '$TRAILER_NAME', expected '$NAME.tar'"
[ "$TRAILER_MD5" = "$(md5sum "$W/$NAME.tar" | awk '{print $1}')" ] || die "tar.md5 trailer md5 mismatch"
echo "   tar.md5 trailer verified: $TRAILER_MD5  $TRAILER_NAME"

# --- verification: extract the kernel back out of the packed image and compare
V=$WS/out/verify-pack
rm -rf "$V"; mkdir -p "$V"
cp "$W/boot.img" "$V/boot.img"
(cd "$V" && "$MAGISKBOOT" unpack boot.img > unpack.log 2>&1) || die "verification unpack failed"
IMG_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
OUT_SHA=$(sha256sum "$V/kernel" | awk '{print $1}')
[ "$IMG_SHA" = "$OUT_SHA" ] || die "kernel sha mismatch: Image=$IMG_SHA extracted=$OUT_SHA"
DTB_SHA=$(sha256sum "$W/kernel_dtb" | awk '{print $1}')
OUT_DTB_SHA=$(sha256sum "$V/kernel_dtb" 2>/dev/null | awk '{print $1}' || true)
[ "$DTB_SHA" = "${OUT_DTB_SHA:-}" ] || echo "   WARNING: DTB differs between build ($DTB_SHA) and packed image (${OUT_DTB_SHA:-none})"
py "$W/avbtool.py" info_image --image "$W/boot.img" > "$WS/logs/avb-info-$(basename "$NAME").txt" 2>&1 || \
  die "avbtool info_image failed on the packed boot.img"

BOOT_SHA=$(sha256sum "$W/boot.img" | awk '{print $1}')
TAR_SHA=$(sha256sum "$ARTIFACTS/$NAME.tar.md5" | awk '{print $1}')
CFG_MD5=$(md5sum "$WS/artifacts/config-baseline.txt" 2>/dev/null | awk '{print $1}' || echo missing)

echo
echo "PACKED  $ARTIFACTS/$NAME.tar.md5"
ls -l "$ARTIFACTS/$NAME.tar.md5"
echo "   boot.img size : $BOOT_SIZE (== $PARTITION_SIZE)"
echo "   boot.img sha256: $BOOT_SHA"
echo "   Image sha256  : $IMG_SHA"
echo "   extracted sha : $OUT_SHA (match)"
echo "   dtb sha256    : $(sha256sum "$W/kernel_dtb" | awk '{print $1}')"
echo "   tar.md5 sha256: $TAR_SHA"
echo "   config md5    : $CFG_MD5"
echo "   avb info      : logs/avb-info-$(basename "$NAME").txt"
tar -tvf "$W/$NAME.tar"
# machine-readable summary for BASELINE-ARTIFACTS.md
{
  echo "artifact=$ARTIFACTS/$NAME.tar.md5"
  echo "tar_md5_sha256=$TAR_SHA"
  echo "boot_img_size=$BOOT_SIZE"
  echo "boot_img_sha256=$BOOT_SHA"
  echo "image_size=$(stat -c%s "$IMAGE")"
  echo "image_sha256=$IMG_SHA"
  echo "extracted_kernel_sha256=$OUT_SHA"
  echo "dtb_bytes=$(stat -c%s "$W/kernel_dtb")"
  echo "dtb_sha256=$(sha256sum "$W/kernel_dtb" | awk '{print $1}')"
  echo "config_md5=$CFG_MD5"
  echo "uname=$(strings "$IMAGE" | grep -m1 'Linux version 4.14')"
} > "$WS/logs/pack-$NAME.txt"
echo "   summary       : logs/pack-$NAME.txt"
