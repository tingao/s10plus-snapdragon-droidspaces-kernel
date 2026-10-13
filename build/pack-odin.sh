#!/bin/sh
# Pack an Odin-flashable AP file from a built kernel.
#
#   ./pack-odin.sh <out-dir> <device-tree-dir> [work-dir]
#
# Produces AP-boot-beyond2qlte-droidspaces.tar.md5 containing boot.img and vbmeta.img.
#
# It needs three inputs that come from outside this repository, and they are not redistributed
# here:
#
#   1. a boot.img from the SAME device to use as a template for the Android boot header
#      (a LineageOS boot image for beyond2qlte is what was used). magiskboot unpacks it, the kernel
#      built above is spliced in, and the header is repacked.
#   2. magiskboot           - from Magisk; unpacks/repacks the Android boot image.
#   3. avbtool.py           - from AOSP external/avb; writes the AVB footer that lets an unsigned
#                             kernel boot.
#
# Set these to your own paths:
MAGISKBOOT=${MAGISKBOOT:-/path/to/magiskboot}
AVBTOOL=${AVBTOOL:-/path/to/avbtool.py}
TEMPLATE=${TEMPLATE:-/path/to/template-boot.img}
VBMETA=${VBMETA:-/path/to/vbmeta.img}          # verification-disabled AVB (flags 3)
NAME=AP-boot-beyond2qlte-droidspaces
PARTITION_SIZE=67108864                        # 64 MiB, the boot partition size on this device

set -eu
OUT="${1:?usage: $0 <out-dir> <device-tree-dir> [work-dir]}"
DT="${2:?usage: $0 <out-dir> <device-tree-dir> [work-dir]}"
W="${3:-$(pwd)/pack}"

for f in "$MAGISKBOOT" "$AVBTOOL" "$TEMPLATE" "$VBMETA"; do
  [ -e "$f" ] || { echo "missing input: $f   (see the header of this script)"; exit 2; }
done

rm -rf "$W"; mkdir -p "$W"; cd "$W"
cp "$TEMPLATE" boot.img
cp "$AVBTOOL" avbtool.py
$MAGISKBOOT unpack boot.img >/dev/null 2>&1

cp "$OUT/arch/arm64/boot/Image" kernel

# The tree emits Image-dtb: "UNCOMPRESSED_IMG" + a 4-byte length, then the kernel, then the device
# DTB from the device tree. Split it back apart.
python3 - "$OUT/arch/arm64/boot/Image" "$OUT/arch/arm64/boot/Image-dtb" <<'PY'
import sys
img = open(sys.argv[1], 'rb').read()
idt = open(sys.argv[2], 'rb').read()
assert idt[:16] == b'UNCOMPRESSED_IMG', 'unexpected Image-dtb header'
assert idt[20:20 + len(img)] == img, 'Image not found at offset 20 of Image-dtb'
open('kernel_dtb', 'wb').write(idt[20 + len(img):])
print("   kernel %d bytes, dtb %d bytes" % (len(img), len(idt) - 20 - len(img)))
PY

$MAGISKBOOT repack boot.img repacked.img >/dev/null 2>&1

# Trim to the end of the last section, then add the AVB footer.
python3 - "$PARTITION_SIZE" <<'PY'
import struct, sys
b = open('repacked.img', 'rb').read()
(ksz, _ka, rsz, _ra, ssz, _sa, _ta, pg, _hv, _os) = struct.unpack('<10I', b[8:48])
end = pg + ((ksz + pg - 1) // pg) * pg + ((rsz + pg - 1) // pg) * pg + ((ssz + pg - 1) // pg) * pg
open('pre-avb.img', 'wb').write(b[:end])
print("   sections end at %d" % end)
PY

python3 avbtool.py add_hash_footer --image pre-avb.img --partition_name boot \
  --partition_size "$PARTITION_SIZE" --flags 3 --algorithm NONE --rollback_index 0 >/dev/null
mv pre-avb.img boot.img

cp "$VBMETA" vbmeta.img

# Pack, then write the trailer AS PART OF THE SAME FILE, with a name that matches the file name.
# Odin rejects a .tar.md5 whose trailer names something else, and rejects a file that is only a
# trailer. Both mistakes cost an evening.
tar -cf "$NAME.tar" boot.img vbmeta.img
cat "$NAME.tar" > "$NAME.tar.md5"
printf '%s  %s\n' "$(md5sum "$NAME.tar" | awk '{print $1}')" "$NAME.tar" >> "$NAME.tar.md5"

echo
tar -tvf "$NAME.tar"
echo "produced: $W/$NAME.tar.md5"
echo "verify with: python3 build/verify-tarmd5.py $W/$NAME.tar.md5"
