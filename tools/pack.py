"""Pack a build.sh install into the tarball a registry part points at, reproducibly.

    python3 -I tools/pack.py PREFIX ee-gcc-2.9-991111-01-macos-arm64.tar.xz

The files sit at the top of the archive, as in the Linux package (`{tc}/bin/ee-gcc`). Entries are sorted, owned by
root, dated 1970 and 0755 or 0644, and no macOS metadata (._ files) goes in, so two builds of the same source give
the same sha256. Prints that sha256.
"""

from __future__ import annotations

import hashlib
import io
import lzma
import os
import sys
import tarfile
from pathlib import Path

CONTENTS = ["COPYING", "COPYING.LIB", "SOURCE.txt", "bin", "ee", "lib"]


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    prefix, out = Path(sys.argv[1]), Path(sys.argv[2])
    if sorted(p.name for p in prefix.iterdir()) != CONTENTS:
        sys.exit(f"{prefix} isn't a build.sh install: expected {', '.join(CONTENTS)}")
    paths = sorted(p for top in CONTENTS for p in [prefix / top, *(prefix / top).rglob("*")])
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as t:
        for p in paths:
            if p.is_symlink():
                sys.exit(f"unexpected link {p}")
            info = t.gettarinfo(p, arcname=p.relative_to(prefix).as_posix())
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            info.mode = 0o755 if info.isdir() or os.stat(p).st_mode & 0o111 else 0o644
            if info.isfile():
                with open(p, "rb") as f:
                    t.addfile(info, f)
            else:
                t.addfile(info)
    data = lzma.compress(buf.getvalue(), preset=9 | lzma.PRESET_EXTREME)
    out.write_bytes(data)
    print(f"{hashlib.sha256(data).hexdigest()}  {out.name}")


if __name__ == "__main__":
    main()
