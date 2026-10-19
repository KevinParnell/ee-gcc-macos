#!/bin/sh
# Build EE-GCC 2.9-ee-991111-01 (driver, cpp, cc1, cc1plus and the EE assembler) natively for macOS with Apple
# clang, from GirianSeed/ee-gcc's copy of Sony's source release, and check it against the original compiler.
#
#   ./build.sh WORKDIR [PREFIX]
#
# WORKDIR holds the download, the sources and the build (about 600 MB); PREFIX gets the install (default
# WORKDIR/ee-gcc-2.9-ee-991111-01), laid out like decomp.wtf's Linux package so the driver finds its tools:
#   bin/ee-gcc, lib/gcc-lib/ee/2.9-ee-991111-01/{cc1,cc1plus,cpp}, ee/bin/as
# The last step compiles a C and a C++ test file and compares the objects with ones made by the original
# Linux compiler (sha256 below); the build fails if they differ. ARCH=x86_64 builds for Intel Macs instead
# (on Apple Silicon that runs under Rosetta).
# The binaries run on macOS 11 or newer (MACOSX_DEPLOYMENT_TARGET overrides that).
set -eu

URL=https://github.com/GirianSeed/ee-gcc/releases/download/src-2.9-ee-991111-01/ee-gcc-2.0.zip
SHA256=99ae6c81801fa0108f436df186daefcc9101b5f402525dae75da8c5e5de728fe
VERSION=2.9-ee-991111-01
# objects the original (decomp.wtf's ee-gcc-2.9-991111-01, run in Linux) makes from tools/selftest.c
SELFTEST_O2_G0=c4b930a7ab20671175c18e6a65e42aab8e67d4890eff338b65c9c7ce033bb352
SELFTEST_O0_G8=29780e3978abdc0676fbc41370d4c15cbf8970a8baa3981b5d2c26cf46c84f34
# and from tools/selftest.cc
SELFTEST_CXX_O2_G0=75a3b13da7d393f8ceeccd91e4b52fe7f866ba7b1efbb9538ae7fb7662fbc158
SELFTEST_CXX_O0_G8=df536d65222652cd23d5638d20d5efdbc12542942fb6a489d577fbfd33df3527

[ $# -ge 1 ] || { sed -n '2,13p' "$0"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"; work=$(cd "$1" && pwd)
out=${2:-$work/ee-gcc-$VERSION}
arch=${ARCH:-$(uname -m)}
case $arch in
  arm64|aarch64) host=aarch64-apple-darwin; archflag="-arch arm64" ;;
  x86_64) host=x86_64-apple-darwin; archflag="-arch x86_64" ;;
  *) echo "unsupported ARCH $arch" >&2; exit 2 ;;
esac
# Apple's toolchain only: a Homebrew gcc or a cross compiler on PATH would build a different compiler.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
unset CC CXX CFLAGS LDFLAGS CPPFLAGS || true
MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.0}; export MACOSX_DEPLOYMENT_TARGET
CC="clang $archflag"
# gnu89 for the K&R code; -fwrapv/-fno-strict-aliasing because 1999 GCC relies on wrapping arithmetic and
# type punning; -fcommon for its tentative definitions; the -Wno-* turn clang's default errors on old C
# (graph.c, cppobscure.c) back into the warnings they were.
CFLAGS="-std=gnu89 -O2 -fwrapv -fno-strict-aliasing -fcommon -fsigned-char -w -Wno-return-mismatch -Wno-int-conversion -Wno-incompatible-pointer-types"
jobs=$(sysctl -n hw.ncpu)

zip=$work/ee-gcc-2.0.zip
if [ ! -f "$zip" ] || [ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" != $SHA256 ]; then
  curl -fL --retry 3 -o "$zip.part" "$URL"
  [ "$(shasum -a 256 "$zip.part" | cut -d' ' -f1)" = $SHA256 ] || { echo "checksum mismatch: $URL" >&2; exit 1; }
  mv "$zip.part" "$zip"
fi

echo "== sources"
rm -rf "$work/pkg" "$work/src" "$work/build"
mkdir -p "$work/pkg" && (cd "$work/pkg" && unzip -q "$zip")
tar xzf "$work/pkg/src/src.tar.gz" -C "$work"
(cd "$work" && patch -p0 -s <pkg/sce-patch/patch)
grep -q "\"$VERSION\"" "$work/src/gcc/version.c" || { echo "unexpected version string" >&2; exit 1; }
# gdb's configure rejects the host, and the compiler doesn't need it. Keep everything else: the top-level
# configure passes gcc --with-gnu-as/--with-gnu-ld because gas/ and ld/ are in the tree, and that turns on
# split %hi/%lo addresses (TARGET_CPU_DEFAULT |20), as in Sony's build. Without ld/ the code changes.
rm -rf "$work/src/gdb"
(cd "$work/src" && patch -p1 -s <"$here/$VERSION/mac-host.patch")
cp "$here/$VERSION/xm-darwin.h" "$work/src/gcc/config/"

echo "== configure ($host)"
# Build in a directory inside the source tree, as the original was: abort () prints __FILE__, which is then
# ../../gcc/expr.c and not ../../src/gcc/expr.c (and the assembler's BFD assertions ../../bfd/...).
obj=$work/src/obj
mkdir -p "$obj" && cd "$obj"
CC="$CC" CFLAGS="$CFLAGS" ../configure --prefix=/usr/local/sce/ee/gcc --host=$host --build=$host --target=ee \
  --enable-c-cpplib --without-sim --disable-sim >configure.log 2>&1 || { tail -20 configure.log; exit 1; }

grep -q 'MASK_MIPS5900|20))' gcc/tm.h || { echo "unexpected TARGET_CPU_DEFAULT: $(cat gcc/tm.h | head -1)" >&2; exit 1; }

echo "== build"
for d in bison libiberty intl bfd opcodes gas; do
  (cd $d && make -j"$jobs" CC="$CC" CFLAGS="$CFLAGS" >make.log 2>&1) || { tail -20 $d/make.log; exit 1; }
done
# The C and C++ parsers come from the in-tree bison 1.25, as in Sony's build (the source has no parse.c).
(cd gcc && make -j"$jobs" CC="$CC" CFLAGS="$CFLAGS" BISON="$obj/bison/bison -L $work/src/bison/" \
  cpp cc1 cc1plus xgcc >make.log 2>&1) || { tail -20 gcc/make.log; exit 1; }

echo "== install to $out"
rm -rf "$out"
mkdir -p "$out/bin" "$out/lib/gcc-lib/ee/$VERSION" "$out/ee/bin"
cp gcc/xgcc "$out/bin/ee-gcc"
cp gcc/cc1 gcc/cc1plus gcc/cpp "$out/lib/gcc-lib/ee/$VERSION/"
cp gas/as-new "$out/ee/bin/as"
cp "$work/src/COPYING" "$work/src/COPYING.LIB" "$out/"
cat >"$out/SOURCE.txt" <<EOF
EE-GCC $VERSION, built for macOS ($host) by build.sh from https://github.com/KevinParnell/ee-gcc-macos,
whose releases also carry a copy of the source below.
Source: $URL (sha256 $SHA256): src/src.tar.gz + sce-patch/patch, then
$VERSION/mac-host.patch (sha256 $(shasum -a 256 "$here/$VERSION/mac-host.patch" | cut -d' ' -f1))
and $VERSION/xm-darwin.h from that repository. GPL-2.0: see COPYING.
EOF

echo "== self-test against the original compiler"
st=$work/selftest; rm -rf "$st"; mkdir -p "$st"; cp "$here/tools/selftest.c" "$here/tools/selftest.cc" "$st/"
cd "$st"
check() {  # check SOURCE FLAGS SHA256
  LC_ALL=C "$out/bin/ee-gcc" $2 -c "$1" -o test.o
  [ "$(shasum -a 256 test.o | cut -d' ' -f1)" = "$3" ] || { echo "self-test FAILED ($1 $2)" >&2; exit 1; }
}
check selftest.c "-O2 -G0" $SELFTEST_O2_G0
check selftest.c "-O0 -G8" $SELFTEST_O0_G8
check selftest.cc "-O2 -G0" $SELFTEST_CXX_O2_G0
check selftest.cc "-O0 -G8" $SELFTEST_CXX_O0_G8
"$out/bin/ee-gcc" --version | head -1
echo "ok: $out"
