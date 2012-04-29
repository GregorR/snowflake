#!/bin/bash -x
# Build a cross-compiler

if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
fi

# Fail on any command failing:
set -e

. "$SNOWFLAKE_BASE"/defs.sh

BINUTILS_VERSION=2.22
GCC_VERSION=4.7.0
MUSL_VERSION=0.8.10
BUSYBOX_VERSION=1.19.4
QUICKLINK_VERSION=0.1

# base files
mkdir -p "$SNOWFLAKE_PREFIX"
if [ ! -e "$SNOWFLAKE_PREFIX/usr" ]
then
    for i in bin etc include lib libexec sbin
    do
        ln -s usr/$i "$SNOWFLAKE_PREFIX/$i"
    done
    for i in boot dev pkg proc sys usr
    do
        mkdir -p "$SNOWFLAKE_PREFIX/$i"
    done
fi

# musl
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr/lib/libc.so" ]
then
    rm -f musl-$MUSL_VERSION/installed # Force it to reinstall
fi
PREFIX="/"
export PREFIX
fetchextract http://www.etalabs.net/musl/releases/ musl-$MUSL_VERSION .tar.gz
cp musl.config.mak musl-$MUSL_VERSION/config.mak
buildmake musl-$MUSL_VERSION
doinstall '' musl-$MUSL_VERSION DESTDIR="$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr"
rm -rf "$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr/bin" # No musl-gcc needed or wanted
unset PREFIX

# busybox
fetchextract http://busybox.net/downloads/ busybox-$BUSYBOX_VERSION .tar.bz2
cp busybox.config busybox-$BUSYBOX_VERSION/.config
buildmake busybox-$BUSYBOX_VERSION LDFLAGS=-static \
    CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc"
doinstall '' busybox-$BUSYBOX_VERSION LDFLAGS=-static \
    CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc" \
    CONFIG_PREFIX="$SNOWFLAKE_PREFIX/pkg/busybox/$BUSYBOX_VERSION/usr"

# quicklink
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/quicklink/$QUICKLINK_VERSION/usr/bin/snowflake-quicklink" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/quicklink/$QUICKLINK_VERSION/usr/bin"
    cp snowflake-quicklink "$SNOWFLAKE_PREFIX/pkg/quicklink/$QUICKLINK_VERSION/usr/bin/"
fi

# binutils
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/binutils/ binutils-$BINUTILS_VERSION .tar.bz2
nolib64 "$SNOWFLAKE_PREFIX/pkg/binutils/$BINUTILS_VERSION/usr"
MAKEFLAGS="$MAKEFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/binutils/$BINUTILS_VERSION" \
    buildinstall root binutils-$BINUTILS_VERSION --host=$TRIPLE --target=$TRIPLE \
        --disable-werror
nolib64end "$SNOWFLAKE_PREFIX/pkg/binutils/$BINUTILS_VERSION/usr"
unset PREFIX

# gcc
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/ gcc-$GCC_VERSION .tar.bz2
nolib64 "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr"
MAKEFLAGS="$MAKEFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION" \
    buildinstall root gcc-$GCC_VERSION --host=$TRIPLE --target=$TRIPLE \
    --enable-languages=c --disable-multilib --disable-libmudflap
nolib64end "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr"
unset PREFIX

# un"fix" headers
rm -rf "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr/lib/gcc/$TRIPLE"/*/include-fixed/

# actually perform the linking
$SUDO chroot "$SNOWFLAKE_PREFIX" /pkg/busybox/$BUSYBOX_VERSION/usr/bin/sh \
    /pkg/quicklink/$QUICKLINK_VERSION/usr/bin/snowflake-quicklink \
    binutils/$BINUTILS_VERSION gcc/$GCC_VERSION
