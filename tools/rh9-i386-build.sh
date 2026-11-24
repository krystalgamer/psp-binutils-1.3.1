#!/bin/sh
# Build binutils-2.14 the way the original psp-gcc 1.3.1 binutils were
# built: on Red Hat Linux 9 (i386) with its gcc 3.2.2-5, binutils
# 2.13.90.0.18-9, glibc 2.3.2-27.9.7 (i686), gettext 0.11.4-7 and texinfo
# 4.3-5, installed in /usr/local/psp/gcc-1.3.1 and stripped with strip -g
# like rpmbuild's brp-strip.  With the "sony" branch checked out the
# result can be compared with the original installation.
#
# Needs: bwrap (bubblewrap) with user namespaces, setarch, python3, curl,
# make and a POSIX shell on the host.
#
# Usage: tools/rh9-i386-build.sh WORKDIR [ORIGINAL_PREFIX]
#   WORKDIR          scratch directory (RPMs, sandbox root, build, install)
#   ORIGINAL_PREFIX  if given, an extracted psp-gcc-1.3.1 installation to
#                    compare the binutils files with
#
# The installation ends up in WORKDIR/install.

set -e
TOOLS=$(cd "$(dirname "$0")" && pwd)
TOP=${TOP:-$(cd "$(dirname "$0")/.." && pwd)}
W=$(mkdir -p "$1" && cd "$1" && pwd)
ORIG=${2:+$(cd "$2" && pwd)}
P=/usr/local/psp/gcc-1.3.1
M=https://mirror.math.princeton.edu/pub/redhat-archive/redhat/linux
GA=$M/9/en/os/i386/RedHat/RPMS
UPD=$M/updates/9/en/os

mkdir -p "$W/rpms"
cd "$W/rpms"
for p in $GA/binutils-2.13.90.0.18-9.i386.rpm $GA/cpp-3.2.2-5.i386.rpm \
	 $GA/gcc-3.2.2-5.i386.rpm $GA/libgcc-3.2.2-5.i386.rpm \
	 $GA/glibc-kernheaders-2.4-8.10.i386.rpm \
	 $GA/gettext-0.11.4-7.i386.rpm $GA/texinfo-4.3-5.i386.rpm \
	 $UPD/i386/glibc-common-2.3.2-27.9.7.i386.rpm \
	 $UPD/i686/glibc-2.3.2-27.9.7.i686.rpm \
	 $UPD/i386/glibc-devel-2.3.2-27.9.7.i386.rpm; do
  [ -f "$(basename $p)" ] || curl -sfLO "$p"
done

# Sandbox root: RH9 /usr/include, and a /usr/lib that holds the RH9 libraries
# and compiler next to symlinks to the host's /usr/lib entries (the host's
# /usr/lib is bound to /tmp/.rh9hostlib inside the sandbox).
rm -rf "$W/root" "$W/lib"
python3 "$TOOLS/unrpm.py" "$W/root" "$W"/rpms/*.rpm
mkdir "$W/lib"
cp -a "$W/root/usr/lib/." "$W/lib/"
find "$W/root/lib" -maxdepth 1 \( -type f -o -type l \) -exec cp -a {} "$W/lib/" \;
for e in /usr/lib/* /usr/lib/.[!.]*; do
  [ -e "$e" ] || [ -L "$e" ] || continue
  n=$(basename "$e")
  [ -e "$W/lib/$n" ] || [ -L "$W/lib/$n" ] || ln -s "/tmp/.rh9hostlib/$n" "$W/lib/$n"
done
for l in $(find "$W/lib" -maxdepth 1 -type l); do
  case $(readlink "$l") in
    ../../lib/*|/lib/*) ln -sfn "$(basename "$(readlink "$l")")" "$l" ;;
  esac
done
G=$W/lib/gcc-lib/i386-redhat-linux/3.2.2
ln -sfn "$W/root/usr/bin/as" "$G/as"
ln -sfn "$W/root/usr/bin/ld" "$G/ld"

rm -rf "$W/install" && mkdir -p "$W/install"
run () {
  bwrap --dev-bind / / \
    --ro-bind /usr/lib /tmp/.rh9hostlib \
    --ro-bind "$W/lib" /usr/lib \
    --ro-bind "$W/root/usr/include" /usr/include \
    --tmpfs /usr/local \
    --bind "$W/install" $P \
    --setenv PATH "$W/root/usr/bin:/usr/bin:/bin" \
    --setenv LC_ALL C \
    setarch i686 "$@"
}

# The generated files that ship with the sources (parsers, catalogs,
# documentation) must look newer than their sources.
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

# The original was configured from a sibling directory of binutils-2.14
# (the regenerated info files name ../../../binutils-2.14/...).  It also
# rebuilt as.info, binutils.info, ld.info and bfd.info with makeinfo 4.3.
rm -rf "$W/src" && mkdir -p "$W/src/binutils-bin"
ln -s "$TOP/binutils-2.14" "$W/src/binutils-2.14"
run sh -c "cd $W/src/binutils-bin &&
  ../binutils-2.14/configure --target=psp --prefix=$P > configure.log 2>&1 &&
  make > make.log 2>&1 &&
  rm -f bfd/doc/bfd.info &&
  make info MAKEINFO='makeinfo --no-split' > info.log 2>&1 &&
  make -C bfd/doc bfd.info MAKEINFO='makeinfo --no-split' >> info.log 2>&1 &&
  make install > install.log 2>&1"

# Sony installed psp-strip as psp-gnu-strip; rpmbuild stripped -g.
mv "$W/install/bin/psp-strip" "$W/install/bin/psp-gnu-strip"
for f in "$W"/install/bin/psp-* "$W"/install/psp/bin/*; do
  run strip -g "$f"
done
echo "The installation is in $W/install"

if [ -n "$ORIG" ]; then
  cd "$W/install"
  same=0; differ=0
  for f in $(find . -type f ! -name dir ! -name libiberty.a | sort); do
    if cmp -s "$f" "$ORIG/$f"; then
      same=$((same + 1))
    else
      differ=$((differ + 1)); echo "differs: $f"
    fi
  done
  echo "$same files identical, $differ different"
fi
