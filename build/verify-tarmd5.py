#!/usr/bin/env python3
"""Verify an Odin .tar.md5 the way Odin does.

A `.tar.md5` is ONE file: the tar body followed by a trailer line

    <32 hex digits>  <name>.tar

Odin rejects a file when either of these is true:

  * the md5 in the trailer does not match the body, or
  * the name in the trailer does not match the file on disk, or the file holds
    only a trailer (a few dozen bytes) because a tool wrote the checksum
    instead of appending it.

Usage:  python3 verify-tarmd5.py AP-boot-beyond2qlte-droidspaces.tar.md5
"""
import hashlib
import os
import re
import sys


def main(path: str) -> int:
    if not os.path.isfile(path):
        print(f"no such file: {path}")
        return 2

    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        tail = fh.read()[-200:]
        m = re.search(rb"([0-9a-f]{32})\s+(\S+)\s*$", tail)
        if not m:
            print(f"  size    : {size} bytes")
            print("  PROBLEM : no md5 trailer found - this is probably not a .tar.md5 at all")
            return 1
        declared = m.group(1).decode()
        inner = m.group(2).decode()
        body_len = size - (m.end() - m.start())
        if body_len < 1024:
            print(f"  size    : {size} bytes")
            print(f"  PROBLEM : the file is only {body_len} bytes of body - this is just a trailer.")
            print("            The tool wrote the checksum instead of appending it. The file must")
            print("            be: tar body + trailer, in one file.")
            return 1
        fh.seek(0)
        digest = hashlib.md5()
        remaining = body_len
        while remaining:
            chunk = fh.read(min(1 << 20, remaining))
            if not chunk:
                break
            digest.update(chunk)
            remaining -= len(chunk)
        computed = digest.hexdigest()

    on_disk = os.path.basename(path)
    expected = on_disk[:-4] if on_disk.endswith(".md5") else on_disk

    print(f"  file          : {on_disk}")
    print(f"  size          : {size} bytes (body {body_len})")
    print(f"  declares      : {declared}")
    print(f"  body md5      : {computed}")
    print(f"  trailer names : {inner}")

    ok = True
    if declared != computed:
        print("  PROBLEM       : the md5 does not match the body - the file is corrupt or truncated")
        ok = False
    if inner != expected:
        print(f"  PROBLEM       : the trailer names '{inner}' but the file is '{on_disk}'.")
        print("                  Odin rejects this. Rename the file to match, or rebuild it.")
        ok = False

    print()
    print("  VERDICT       : " + ("ODIN WILL ACCEPT THIS" if ok else "ODIN WILL REJECT THIS"))
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
