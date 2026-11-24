# psp-gcc 1.3.1 binutils reconstruction

This repository rebuilds the source of the binutils that ship with Sony's
PSP compiler `psp-gcc` 1.3.1 (`GNU assembler 2.14+allegrex-2.2.1-psp-1.3.1`,
BFD `2.14+allegrex-vfpu-2.2.1-psp-1.3.1 20030612`), so that they can be
rebuilt and kept running on modern 64-bit hosts. The original release
binaries are 32-bit x86 Linux programs. Reference archive:
<https://github.com/decompme/compilers/releases/download/compilers/psp-gcc-1.3.1.tar.gz>.

Sony distributed its toolchain sources and patches to licensed developers
only, through the PlayStation developer network (DevNet); they were never
publicly released. This tree does not use them. `binutils-2.14/` starts
from pristine FSF binutils 2.14 (tag `fsf-binutils-2.14`), and every PSP
change on top was reconstructed from the public release, whose binaries
have symbols:

- strings, symbols and data tables (the opcode table is identical entry
  for entry)
- the line numbers embedded by `assert` and `as_fatal`
- decompiled functions, compared function by function
- the installed linker scripts, catalogs, man pages and info files; the
  original build regenerated `bfd.info`, which documents the order of the
  new `bfd_mach_*` numbers

The VFPU assembler and disassembler code of the GPL homebrew PSP toolchain
(psptoolchain's `binutils-2.16.1-PSP.patch`) clearly descends from Sony's;
it served as a starting point and was corrected against the binaries
(Sony's `-mno-ulsw`, `-vmmul-trans`, ulv.q/usv.q address forms and other
details are not in it, and some homebrew additions are not in Sony's).

Because the patches were rebuilt from binaries, code that left no trace in
them, such as comments and formatting, is not necessarily Sony's. Where
the order of switch cases or declarations could only be told from register
allocation, it was chosen to reproduce the original compiler's choices.
GCC is covered by separate repositories.

## Branches

- **`sony`**: FSF binutils 2.14 plus the reconstructed PSP changes, and
  nothing else. Built on Red Hat Linux 9 with its gcc 3.2.2, as the
  original was, it reproduces the original installation except for two
  functions (see "Verification").
- **`master`**: `sony` plus the changes needed to build and run correctly
  on modern and 64-bit hosts, the build script, the Red Hat 9 build tool
  and this README. Its output is the same as the original's.

Patch series:

```sh
git format-patch fsf-binutils-2.14..sony -- binutils-2.14   # the PSP changes
git format-patch sony..master -- binutils-2.14              # the host/x64 port
```

## Changes

**PSP changes (`sony`):**

- **Target:** `psp` is `mipspspel-scei-elf` (`config.sub`), assembling for
  Allegrex by default (`gas/configure`).
- **Version:** BFD reports `2.14+allegrex-vfpu-2.2.1-psp-1.3.1`, the other
  tools `2.14+allegrex-2.2.1-psp-1.3.1`.
- **BFD and readelf:** Allegrex 2.0, 3.0 and 3.1 machines
  (`E_MIPS_MACH_ALLEGREX2/3/31`, `bfd_mach_mips_allegrex2/3/31`), MIPS II
  based.
- **ld:**
  - looks for libraries and linker scripts in the PSP SDK first,
    `$SCE_PSP_SDK_HOME/lib` (default `/usr/local/psp/devkit/lib`); the
    scripts are not built into the linker
  - defaults to `-G 0`
- **opcodes:** the Allegrex instructions and the VFPU instruction set, and
  their disassembly (VFPU registers, prefixes, constants, rotations and
  half-precision immediates).
- **gas:**
  - Allegrex instructions and the VFPU, with operand and register-overlap
    checks
  - defaults: Allegrex 3.1, EABI, MIPS II, `-G 0`, VFPU enabled;
    `.set allegrex`
  - `-mno-ulsw` (default) expands `ulw`/`usw` byte by byte, since Allegrex
    3.1 has no `lwl`/`lwr`/`swl`/`swr`; `-mulsw` brings them back
  - `-vmmul-trans` (default) transposes `vmmul`'s first source
  - `ulv.q`/`usv.q` with an address operand
  - no double-precision FP and no COP2 loads and moves on Allegrex; only
    Allegrex 3.1 rotates
  - VFPU prefixes, HI/LO interlocks, no coprocessor delays on Allegrex
  - ELF symbol sizes for functions at `.end`
  - VFPU load/store offsets in REL relocations

**Host port (`master`):**

- `bfd/archive.c`: write archive header fields without a fortified
  `sprintf` (2.14 lets each field's terminating NUL spill into the next
  one, which `_FORTIFY_SOURCE` aborts on); archives are byte-for-byte the
  same.
- `build-psp-binutils.sh` compiles the old C with current GCC and keeps
  make from regenerating the parsers, catalogs and documentation that ship
  with the sources.

## Building

```sh
./build-psp-binutils.sh install
```

`build-psp-binutils.sh` configures with the same options as the original,
installs to `PREFIX` (default `/usr/local/psp/gcc-1.3.1`) and, like the
original, installs `psp-strip` as `psp-gnu-strip`. For details, see the
comments at the top of the script.

The installed `psp-ld`, like Sony's, reads its linker scripts from the PSP
SDK (`$SCE_PSP_SDK_HOME/lib/ldscripts`); the generated scripts, identical
to the original's, are in `$PREFIX/psp/lib/ldscripts`.

## Verification

### `sony` on the original toolchain

`tools/rh9-i386-build.sh WORKDIR [ORIGINAL_PREFIX]` builds the `sony`
branch the way the original was built and compares the result with an
extracted original installation. It needs `bwrap`; no root and no Red Hat
installation required.

- **Environment:**
  - Red Hat Linux 9 gcc 3.2.2-5 and binutils 2.13.90.0.18-9
  - glibc 2.3.2-27.9.7 (i686), gettext 0.11.4-7 and texinfo 4.3-5
  - default `-g -O2`, configured from a sibling directory of
    `binutils-2.14`
  - installed in `/usr/local/psp/gcc-1.3.1`, binaries stripped with
    `strip -g` like rpmbuild's `brp-strip`
- **Results:**
  - **byte-identical to the original:** `psp-ld`, `psp-ar`, `psp-ranlib`,
    `psp-nm`, `psp-objcopy`, `psp-gnu-strip`, `psp-readelf`, `psp-size`,
    `psp-strings`, `psp-addr2line`, `psp-c++filt`, the `psp/bin` copies,
    the linker scripts, the man pages, the message catalogs and the info
    files (80 files)
  - **`psp-as`:** every function is identical except `macro`, where a few
    dozen register choices of the original compiler differ (and a
    shifted address in `load_address`)
  - **`psp-objdump`:** identical except a few register choices in
    `print_insn_args`
  - these differences come from the original compiler's register
    allocation (and, in `macro`, one shared instruction tail it chose
    differently); the code is otherwise the same instruction for
    instruction

`lib/libiberty.a` and `psp/lib/libiberty.a` in the original installation
come from GCC.

### `master` on a modern x86_64 host

Built with GCC 15 on Ubuntu, compared with the original 32-bit binaries:

- 200,000 random instruction words disassemble identically, and the
  28,000 valid instructions among them reassemble to identical objects
- the 2,124 assembly files the original `cc1` produces from GCC's
  `gcc.c-torture/compile` tests at `-O2` and `-O0 -g` assemble to
  identical objects with identical messages
- `objdump -dr`, `nm`, `readelf -a`, `size`, `objdump -h`, `objcopy -O
  binary`, `strip` and links with the original linker script give
  identical output for 588 of those objects; archives made by `ar` are
  identical apart from timestamps
- the installed linker scripts, man pages and message catalogs are the
  original's
