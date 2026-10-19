# EE-GCC 2.9-ee-991111-01 for macOS (Apple Silicon)

A native arm64 build of EE-GCC 2.9-ee-991111-01, the PlayStation 2 Emotion Engine C compiler from Sony's 1999
SDK, for matching decompilation on a Mac without a Linux VM: the driver (`ee-gcc`), `cpp`, `cc1` and the EE
assembler (`as`), built from Sony's GPL source release with a host port for 64-bit macOS. C only.

Its output is checked byte for byte against the original Linux binaries that decomp.wtf installs
(decompme/compilers `ee-gcc2.9-991111-01.tar.xz`).

## Download

The release [`2.9-ee-991111-01`](https://github.com/KevinParnell/ee-gcc-macos/releases/tag/2.9-ee-991111-01) has:

- `ee-gcc-2.9-991111-01-macos-arm64.tar.xz`, sha256
  `c8d496dc460ff19ae93f57b423cbb9332744df653d66648883d32cc5cb6fdc9e`: `bin/ee-gcc`,
  `lib/gcc-lib/ee/2.9-ee-991111-01/{cc1,cpp}`, `ee/bin/as`, `COPYING`, `COPYING.LIB`, `SOURCE.txt`. The layout
  is the Linux package's, so anything that runs `{tc}/bin/ee-gcc -c ...` works unchanged.
- `ee-gcc-2.0.zip`: a copy of the source it's built from (GirianSeed/ee-gcc, release `src-2.9-ee-991111-01`,
  sha256 `99ae6c81801fa0108f436df186daefcc9101b5f402525dae75da8c5e5de728fe`).

It runs on macOS 11 or newer on Apple Silicon. The binaries are ad-hoc signed and link only libSystem.

## Verification

On 3,607 compiles of C (CC0 demo programs, zlib 1.1.4, generated torture cases and gcc.c-torture; -O0 to -O3,
-G0 and -G8, `-g`), all 3,379 that the original completes give byte-identical objects and byte-identical `-S`
output: every section, the symbol table and the relocations. The other 228 fail in both, mostly c-torture tests
that need headers the package doesn't ship.

Also checked: the generated sources (insn-*, genrtl, the bison 1.25 C parser) are byte-identical to ones
generated on Linux; a `-O0` build of cc1 gives the same results; so do builds with every local pre-filled
(`-ftrivial-auto-var-init`) and with heap scribbling; an ASan + UBSan build (which found the three memory bugs
below); several locales, including Shift-JIS bytes in string literals. Two builds give byte-identical binaries.

## Build it yourself

    ./build.sh WORKDIR

About a minute on an M-series Mac, with only Apple's command-line tools. It downloads the source zip (sha256
pinned), applies Sony's `sce-patch` and `2.9-ee-991111-01/mac-host.patch`, configures as Sony did
(`--target=ee --enable-c-cpplib`), builds with Apple clang, installs to `WORKDIR/ee-gcc-2.9-ee-991111-01`, and
fails unless `tools/selftest.c` compiles to the original compiler's objects. Then

    python3 -I tools/pack.py WORKDIR/ee-gcc-2.9-ee-991111-01 ee-gcc-2.9-991111-01-macos-arm64.tar.xz

packs it reproducibly: the same sha256 as the release.

## What the port changes (`2.9-ee-991111-01/mac-host.patch`)

| Part | Why |
| --- | --- |
| config.sub, gcc/configure, `xm-darwin.h` | Accept a 64-bit macOS host. `long` and pointers are 64-bit here; HOST_WIDE_INT stays `long long`, as the r5900 target forces on every host. |
| libiberty/strerror.c, include/obstack.h | Build fixes for modern C and the macOS SDK; the code they produce is unchanged. |
| gcc/expr.h, gcc/expr.c | **Crash fix.** GCC calls its generated `gen_*` functions (K&R, not variadic) through `rtx (*)(rtx, ...)`. Apple arm64 passes variadic arguments on the stack, so the operands arrived as garbage and `cc1` crashed on `int add(int a, int b) { return a + b; }`. The pointers are now unprototyped, as `genoutput.c` already declares the table. |
| gcc/real.c, gcc/config/mips/mips.c | **Codegen fix.** The original host's `long` is 32 bits, so real.c's 32-bit target words are negative there when bit 31 is set, and the original compiles `long long f(void) { union { double d; long long l; } u; u.d = 1.1; return u.l; }` at -O1/-O2 to `dli $2,0xffffffff9999999a` (a bug in the original). real.c now sign-extends the words as a 32-bit `long` would, and mips.c prints only their low 32 bits. |
| gcc/dbxout.c | **Debug-info fix.** With `-g`, stabs type ranges switch to octal at gdb's 32-bit `long`, as the original writes them. |
| gcc/haifa-sched.c | **Memory fix (ASan).** `init_rgn_data_dependences` cleared an `int` array with `n * sizeof (rtx)` bytes, past its `alloca` block on a 64-bit host. It now clears `n * sizeof (int)`, what the original cleared. |
| gcc/jump.c | **Memory fix (ASan).** `delete_barrier_successors` read `SET_SRC`/`SET_DEST` of every jump's pattern without checking that it is a `SET`. Now it checks, as later GCC versions do. |
| gcc/loop.c | **Memory fix (ASan).** `find_and_verify_loops` stored a LOOP_CONT note outside any loop at `loop_number_loop_cont[-1]`. With the original's packed `alloca` blocks that is `loop_number_cont_dominator[max_loop_num - 1]`; the port stores it there explicitly. |

One build trap: gcc's configure turns on split `%hi`/`%lo` addressing only when GNU ld is in the source tree, so
`build.sh` keeps the full tree (removing only `gdb/`) and checks `tm.h`.

## Not done

- **C++ (`cc1plus`)**: it builds, but hits internal compiler errors on many g++ tests where the original
  doesn't; the C++ front end needs its own 64-bit audit. `build.sh` doesn't build it.
- **Intel Macs**: `ARCH=x86_64 ./build.sh` builds and passes the self-test, but 3 of 3,379 c-torture compiles at
  `-O3 -G8 -funroll-loops` differ in `-S` label numbers (the objects are identical). Not released until that's
  understood.
- **2.96 (2.96-ee-001003-1)**: no public source.

## License

GPL-2.0, like the compiler: see `COPYING`. The binaries are built from the source zip in the release (also at
the GirianSeed/ee-gcc URL above) plus `2.9-ee-991111-01/mac-host.patch` and `xm-darwin.h` in this repository.
