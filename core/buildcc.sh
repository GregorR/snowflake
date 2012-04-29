#!/bin/bash -x
# Build a cross-compiler

if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
fi

# Fail on any command failing:
set -e

. "$SNOWFLAKE_BASE"/defs.sh

# Switch to the CC prefix for all of this
PREFIX="$CC_PREFIX"

BINUTILS_VERSION=2.22
GCC_VERSION=4.7.0
MUSL_VERSION=0.8.10
LINUX_VERSION=3.3.4

# binutils
fetchextract http://ftp.gnu.org/gnu/binutils/ binutils-$BINUTILS_VERSION .tar.bz2
buildinstall 1 binutils-$BINUTILS_VERSION --target=$TRIPLE

# gcc 1
fetchextract http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/ gcc-$GCC_VERSION .tar.bz2
buildinstall 1 gcc-$GCC_VERSION --target=$TRIPLE \
    --enable-languages=c --with-newlib --disable-multilib --disable-libssp \
    --disable-libquadmath --disable-threads --disable-decimal-float \
    --disable-shared --disable-libmudflap --disable-libgomp

# linux headers
fetchextract http://www.kernel.org/pub/linux/kernel/v3.0/ linux-$LINUX_VERSION .tar.bz2
cp linux.config linux-$LINUX_VERSION/.config
if [ ! -e linux-$LINUX_VERSION/installedheaders ]
then
    pushd linux-$LINUX_VERSION
    make headers_install INSTALL_HDR_PATH="$CC_PREFIX/$TRIPLE"
    touch installedheaders
    popd
fi

# musl in CC prefix
PREFIX="$CC_PREFIX/$TRIPLE"
export PREFIX
fetchextract http://www.etalabs.net/musl/releases/ musl-$MUSL_VERSION .tar.gz
cp musl.config.mak musl-$MUSL_VERSION/config.mak
buildmake musl-$MUSL_VERSION
doinstall '' musl-$MUSL_VERSION
unset PREFIX
PREFIX="$CC_PREFIX"

# gcc 2
buildinstall 2 gcc-$GCC_VERSION --target=$TRIPLE \
    --enable-languages=c --disable-multilib --disable-libmudflap

# un"fix" headers
rm -rf "$CC_PREFIX/lib/gcc/$TRIPLE"/*/include-fixed/
