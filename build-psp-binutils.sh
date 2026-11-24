#!/bin/sh
# Build the reconstructed binutils of psp-gcc 1.3.1
# (2.14+allegrex-vfpu-2.2.1-psp-1.3.1) on a modern 64-bit Linux host.
#
# Usage: ./build-psp-binutils.sh [build|install]
#
# Environment:
#   PREFIX  installation prefix (default /usr/local/psp/gcc-1.3.1)
#   BUILD   build directory     (default ./build, next to binutils-2.14,
#           which is how the original was configured)
#   JOBS    parallel make jobs  (default 4)
#   CC      host C compiler     (default gcc)
#
# The installed psp-ld looks for its linker scripts and libraries in the
# PSP SDK, $SCE_PSP_SDK_HOME/lib (default /usr/local/psp/devkit/lib), as
# Sony's did; the generated scripts are also installed in
# $PREFIX/psp/lib/ldscripts.
#
# The original installation renamed bin/psp-strip to bin/psp-gnu-strip;
# "install" does the same.  The original also regenerated as.info,
# bfd.info, binutils.info and ld.info with makeinfo 4.3; if makeinfo is
# missing, empty info files are installed instead.

set -e

TOP=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-/usr/local/psp/gcc-1.3.1}
BUILD=${BUILD:-$TOP/build}
JOBS=${JOBS:-4}
STEP=${1:-build}

# binutils 2.14 is old K&R-ish C; let a modern host compiler accept it.
HOST_CC="${CC:-gcc} -std=gnu89 -fcommon -w -fpermissive"
HOST_CC="$HOST_CC -Wno-error=implicit-function-declaration -Wno-error=implicit-int"
HOST_CC="$HOST_CC -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"

# A checkout gives every file the same age, so make would try to rebuild
# the generated parsers, catalogs and documentation that ship with the
# sources (with bison, msgfmt and makeinfo of today).  Make the generated
# files newer than their sources.
(
  cd "$TOP/binutils-2.14"
  for y in $(find . -name '*.y' -o -name '*.l'); do
    b=${y%.*}
    for g in "$b.c" "$b.h"; do [ -f "$g" ] && touch "$g"; done
  done
  find . \( -name aclocal.m4 -o -name '*.pot' \) -exec touch {} +
  find . \( -name configure -o -name config.in -o -name Makefile.in \) -exec touch {} +
  find . \( -name '*.gmo' -o -name '*.info' -o -name '*.info-[0-9]*' \) -exec touch {} +
)

mkdir -p "$BUILD"
cd "$BUILD"
if [ ! -f config.status ]; then
  if [ "$(cd .. && pwd)" = "$TOP" ]; then
    SRC=../binutils-2.14
  else
    SRC=$TOP/binutils-2.14
  fi
  CC="$HOST_CC" $SRC/configure --target=psp --prefix="$PREFIX"
fi

make -j"$JOBS"

if [ "$STEP" = install ]; then
  make install
  if command -v makeinfo >/dev/null 2>&1; then
    rm -f bfd/doc/bfd.info
    make info MAKEINFO="makeinfo --no-split"
    make -C bfd/doc bfd.info MAKEINFO="makeinfo --no-split"
    make install-info
  fi
  mv -f "$PREFIX/bin/psp-strip" "$PREFIX/bin/psp-gnu-strip"
fi
