# EE-GCC 2.9-ee-991111-01 for macOS (Apple Silicon)

A native arm64 build of EE-GCC 2.9-ee-991111-01, the PlayStation 2 Emotion Engine compiler from Sony's 1999 SDK,
for matching decompilation on a Mac without a Linux VM: the driver (`ee-gcc`), `cpp`, `cc1`, `cc1plus` and the
EE assembler (`as`), built from Sony's GPL source release with a host port for 64-bit macOS. C and C++.

Its output is checked byte for byte against the original Linux binaries that decomp.wtf installs
(decompme/compilers `ee-gcc2.9-991111-01.tar.xz`).

## Download

The release [`2.9-ee-991111-01-r2`](https://github.com/KevinParnell/ee-gcc-macos/releases/tag/2.9-ee-991111-01-r2) has:

- `ee-gcc-2.9-991111-01-macos-arm64.tar.xz`, 1,525,368 bytes, sha256
  `18996eccef8b68243cdc545bb4cd7e8783645852d0fae037725d7b7c76f9b63d`: `bin/ee-gcc`,
  `lib/gcc-lib/ee/2.9-ee-991111-01/{cc1,cc1plus,cpp}`, `ee/bin/as`, `COPYING`, `COPYING.LIB`, `SOURCE.txt`. The
  layout is the Linux package's, so anything that runs `{tc}/bin/ee-gcc -c ...` works unchanged.
- `ee-gcc-2.0.zip`: a copy of the source it's built from (GirianSeed/ee-gcc, release `src-2.9-ee-991111-01`,
  sha256 `99ae6c81801fa0108f436df186daefcc9101b5f402525dae75da8c5e5de728fe`).

The first release, [`2.9-ee-991111-01`](https://github.com/KevinParnell/ee-gcc-macos/releases/tag/2.9-ee-991111-01),
is C only (no `cc1plus`) and stays up for anything that pins it.

It runs on macOS 11 or newer on Apple Silicon. The binaries are ad-hoc signed and link only libSystem.

## Verification

All 6,614 corpus compiles that the original completes (3,379 C, 3,235 C++) give byte-identical objects and
byte-identical `-S` output with the native build, compared raw: every section, the symbol table and the
relocations. That covers -O0 to -O3, -G0 and -G8, `-g`, and C++ with and without exceptions and RTTI. Every case
the original rejects (1,973 of the 8,587), the native build rejects too, with the same messages. The corpus is
CC0 demo programs, zlib 1.1.4, generated torture cases, gcc.c-torture, g++.old-deja and C++ torture cases.

## Build it yourself

    ./build.sh WORKDIR [PREFIX]

About two minutes on an M-series Mac, with only Apple's command-line tools. It downloads the source zip (sha256
pinned), applies Sony's `sce-patch` and `2.9-ee-991111-01/mac-host.patch`, configures as Sony did
(`--target=ee --enable-c-cpplib`), builds with Apple clang, installs to PREFIX (default
`WORKDIR/ee-gcc-2.9-ee-991111-01`), and fails unless `tools/selftest.c` and `tools/selftest.cc` compile to the
original compiler's objects. Then

    python3 -I tools/pack.py PREFIX ee-gcc-2.9-991111-01-macos-arm64.tar.xz

packs it reproducibly: the same sha256 as the release.

## What the port changes (`2.9-ee-991111-01/mac-host.patch`)

| Part | Why |
| --- | --- |
| config.sub, gcc/configure, `xm-darwin.h` | Accept a 64-bit macOS host. `long` and pointers are 64-bit here; HOST_WIDE_INT stays `long long`, as the r5900 target forces on every host. |
| libiberty/strerror.c, include/obstack.h | Build fixes for modern C and the macOS SDK; the code they produce is unchanged. |
| gcc/expr.h, gcc/expr.c | **Crash fix.** GCC calls its generated `gen_*` functions (K&R, not variadic) through `rtx (*)(rtx, ...)`. Apple arm64 passes variadic arguments on the stack, so the operands arrived as garbage. Reproducer: `int add(int a, int b) { return a + b; }` crashed `cc1` at every -O. The pointers are now unprototyped, as `genoutput.c` already declares the table. |
| gcc/real.c, gcc/config/mips/mips.c | **Codegen fix.** The original host's `long` is 32 bits, so real.c's 32-bit target words are negative there when bit 31 is set. In 64-bit words, `operand_subword` then ORs the sign-extended low word over the high one: the original compiles `long long f(void) { union { double d; long long l; } u; u.d = 1.1; return u.l; }` at -O1/-O2 to `dli $2,0xffffffff9999999a` (a bug in the original). Unpatched, the port gave `0x3ff199999999999a`. real.c now sign-extends the words as a 32-bit `long` would, and mips.c prints only their low 32 bits. |
| gcc/dbxout.c | **Debug-info fix.** The stabs for a type's range switch to octal at gdb's 32-bit `long`: with `-g`, the original writes `int:t1=r1;000000000000020000000000;000000000000017777777777;`, the unpatched port `-2147483648;2147483647`. |
| gcc/haifa-sched.c | **Memory fix (found by ASan).** `init_rgn_data_dependences` cleared the `int` array `bb_pending_lists_length` with `n * sizeof (rtx)` bytes: 4 per element on the original, 8 here, so it wrote past its `alloca` block. It now clears `n * sizeof (int)`, exactly what the original cleared. |
| gcc/jump.c | **Memory fix (found by ASan).** `delete_barrier_successors` read `SET_SRC`/`SET_DEST` of every jump's pattern without checking that it is a `SET`; for a `(return)` or a dispatch table it read the next object in memory, whose contents depend on the host. Now it checks, as later GCC versions do. On the original the test could only have been true if two stray words happened to equal `pc_rtx`. |
| gcc/loop.c | **Memory fix (found by ASan).** `find_and_verify_loops` stored a LOOP_CONT note that lies outside any loop at `loop_number_loop_cont[-1]` (c-torture `compile/950124-1.c` at -O1 and up). The original's disassembly shows its `alloca` blocks packed back to back, `n * 4` bytes each, so on its host that store hit `loop_number_cont_dominator[max_loop_num - 1]`. The port now stores it there explicitly instead of writing outside the block. |
| gcc/cp/cp-tree.h, gcc/cp/errfn.c, gcc/cp/typeck2.c | **C++ crash fix.** The same variadic trap as gen_*, the other way round: `cp_error`, `cp_warning`, `cp_pedwarn` and their `_at` forms are variadic, but cp-tree.h declared them `()`. All 826 calls passed their arguments in registers while the callee read them from the stack, so most diagnostics printed garbage or crashed: 684 of the 4,936 g++ compiles ended in "Internal compiler error" where the original didn't (231 after this fix, 0 after the decl.c and call.c fixes below). They are prototyped now. errfn.c also called `error`/`warning`/`pedwarn` (variadic) and `compiler_error` (K&R) through one unprototyped pointer; each is now called the way it is defined. |
| gcc/cp/decl.c | **C++ memory fix (found by ASan).** In `grokdeclarator`, a destructor's name was reached through `next = &name`, a variable local to a block that had ended when the loop read it (stack-use-after-scope). The original's stack slot still held the value; clang reuses or drops it. It now lives as long as the loop. |
| gcc/cp/call.c | **C++ codegen fix.** `add_function_candidate` passed an uninitialised `convs` to `add_candidate` for candidates that aren't viable; nothing reads it, but clang treats passing an uninitialised value as undefined and removed that path, so those candidates counted as viable. `foo f;` was "ambiguous" between `foo()` and the implicit `foo(const foo &)`. It starts as NULL_TREE. |
| gcc/cp/rtti.c | **C++ codegen fix (found with a zero-filled-locals build).** `build_x_typeid` read an uninitialised `nonnull`, which `resolves_to_fixed_type_p` only ever sets to 1. In the original it held stack leftovers, never 0 in any test (40 `typeid (*p)` contexts at two flag sets, plus the corpus), so `typeid (*p)` got no null check. It starts at 1, instead of depending on the port's stack (with 0, every such `typeid` calls `__throw_bad_typeid` on null). |
| gcc/cp/decl2.c, gcc/cp/pt.c, gcc/cp/typeck.c | **C++ codegen fix: argument order.** C leaves the order in which a call's arguments are evaluated unspecified. The original was built with GCC 2.7.2 on i386 (its `-v` says so), which evaluates them right to left; clang goes left to right. When template code is instantiated, `build_expr_from_tree (op0)` and `build_expr_from_tree (op1)` as arguments of one call instantiate templates in that order, and the order decides the order of the functions in the object: in g++.pt `sizeof.C` the original emits `bar<15>` before `bar<8>`. In the 29 calls where two arguments can instantiate templates, synthesize methods or give diagnostics (`build_expr_from_tree`, `tsubst_copy`, `tsubst_expr`, `rationalize_conditional_expr`, `build_component_ref`, `build_modify_expr`), the later arguments are now computed first. The other calls with several side-effecting arguments (about 130 in cp/ and 540 in the shared back end, listed from clang's AST) only allocate or look things up, so their order doesn't show in the output; the C results above cover the back end. |
| gcc/except.c | **EH fixes (shared with C `-fexceptions`).** `remove_handler` compared handler labels by pointer, also for the regions of functions already compiled, whose labels had been freed: a new label at the same address removed an unrelated function's handler and its exception table entry (C++ torture `eh.cc` at -O1/-O2 lost `rethrower`'s entry). Which labels collide depends on the host's object sizes, so it compares the unique label numbers now. `get_first_handler` read `function_eh_regions[-1]` for a region it couldn't find; on the original that is the malloc chunk header and the compiler crashed (g++.mike `p700.C`, g++.robertl `eb101.C` at -O2). It raises SIGSEGV now, so the messages are the same. |
| gcc/cp/typeck.c, gcc/c-typeck.c, gcc/cp/typeck2.c, gcc/cp/error.c | **LONG32, diagnostics and names.** The `-Wsign-compare` check for "comparison of promoted ~unsigned" stops at the original's 32-bit `long`; an enum value with no enumerator is printed through a 32-bit `long`; a 128-bit constant printed with `"%x%08x"` and two 64-bit words shows the two halves of the high word, as i386's printf did. These reach error messages and `__PRETTY_FUNCTION__` only. |
| gcc/cp/cp-tree.h `IS_SIGNATURE` | **C++ fix (found on x86_64).** A pointer-to-member-function type keeps its RECORD_TYPE in `TYPE_LANG_SPECIFIC`, and `IS_SIGNATURE` read a `struct lang_type` flag from that tree: the low byte of its null `TREE_TYPE` on i386, part of a `TREE_CHAIN` address on a 64-bit host. On x86_64 `(int (A::*)()) 0` became a "signature type" (an error). Only class types are checked now. |
| gcc/sibcall.c | **Codegen fix (found on x86_64).** `optimize_sibling_and_tail_recursive_calls` calls `find_basic_blocks`, undeclared there, with 3 of its 4 arguments, so `do_cleanup` was whatever lay in the fourth place: in the port a register left over from the previous call, 0 or not depending on how jump.c was compiled. x86_64 kept dead inlined loops (c-torture `960209-1.c` at -O3: 3 compiles had other label numbers). On the original it was `insns`, still on the stack from the call before (GCC defers the pop), never 0. It passes 1. |
| gcc/tree.c | **Reproducible names.** A C++ file that defines no global object names its EH frame function and anonymous namespaces after the file plus 6 characters made from the time of day and the pid (`_GLOBAL_$F$src_g___g__.eh_new1.CShGfFQ`), so the original never gives the same object twice. The port adds 0 there, which is what the original adds when `tools/fixed-clock.so` is preloaded (see Verification): both then give the same names every time. |
| gcc/expr.c, gcc/optabs.c, gcc/function.c, gcc/integrate.c, gcc/combine.c, gcc/c-common.c, gcc/config/mips/mips.c, gcc/config/mips/mips.md | **Argument order in the back end (found by comparing `-da` dumps).** Where one argument of a call can make a pseudo register or emit an insn before another (complex moves, highpart multiplies, `__builtin_apply_args`, multiword compares and binops, parameter moves, inlined calls, block moves, the r5900 multiply expanders), the later arguments are computed first, as the original's build compiler did. The objects were already the same; the RTL (register numbers) wasn't, so this removes a way to differ. |
| gcc/haifa-sched.c | **`-da` fix.** `get_visual_tbl_length` wrote 36 bytes into a 35-byte `alloca`; the original's `alloca` rounded to 36, the port's fortified `sprintf` aborted every `-da` compile that scheduled. `print_value` prints a CONST_DOUBLE's words through a 32-bit `long` (LONG32). |
| gcc/cp/decl.c, gcc/tree.c, gcc/integrate.c, gcc/toplev.c | **Error recovery, so rejected code gets the same messages.** Error recovery reads fields that `error_mark_node` (an ERROR_MARK node, 12 bytes on i386) doesn't have. On the original it was followed by `error_mark_list` and `this_identifier`, so those reads found their fields; in the port they found other nodes' fields. `error_mark_node` now has room for every field and holds what the original read in those that the g++ tests reach (`TREE_OPERAND 0` is `error_mark_node`, `DECL_CONTEXT` is 4, the rest 0), found with a build that reported every read past the end of the node and the field offsets of both hosts. tree.c: error recovery also reads other nodes' fields from identifiers (`TYPE_MAIN_VARIANT` in g++.pt `crash1.C`, `DECL_LANG_SPECIFIC` in `friend37.C`; no other test does). On the original those offsets fell in the identifier's name and the nodes after it, which held 0 and 1 there, so both crashed; identifiers now have room for every field, all 0, which crashes the same way. integrate.c: after errors `DECL_RESULT` can be null, and the original loaded `DECL_RTL` from it before testing for a void function and crashed; clang moved the load to where it is used, so it is volatile now. toplev.c: macOS raises SIGBUS for some bad accesses that i386 Linux reports as SIGSEGV, and the driver prints the number, so cc1 dies of SIGSEGV instead. |
| `#line` in 15 files | **`abort ()` messages.** `abort ()` prints `__FILE__` and `__LINE__`. A `#line N` after each change above that adds or removes lines (in a file that calls `abort ()`) gives the following lines their original numbers, and the mips.md changes, which are copied into insn-emit.c, keep their line counts. Checked by preprocessing: every `abort ()` in the patched files expands with the line it has in the original source. |

One build-procedure trap: gcc's configure turns on split `%hi`/`%lo` addressing (TARGET_CPU_DEFAULT `|20`)
only when GNU ld is in the source tree. Without `ld/`, the compiler addresses globals with assembler macros
(`lw $2,g`) and nothing matches. `build.sh` keeps the full tree, removes only `gdb/` (its configure rejects
the host) and checks `tm.h`.

## Not done

- **Intel Macs**: `ARCH=x86_64 ./build.sh` builds and passes the same checks, but isn't part of this release.
- **2.96 (2.96-ee-001003-1)**: no public source.

## License

GPL-2.0, like the compiler: see `COPYING`. The binaries are built from the source zip in the release (also at
the GirianSeed/ee-gcc URL above) plus `2.9-ee-991111-01/mac-host.patch` and `xm-darwin.h` in this repository.
