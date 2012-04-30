#!/bin/bash -x
# Build a root filesystem
# 
# Copyright (C) 2012 Gregor Richards
# 
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
fi

# Fail on any command failing:
set -e

. "$SNOWFLAKE_BASE"/defs.sh

# base files
mkdir -p "$SNOWFLAKE_PREFIX"
if [ ! -e "$SNOWFLAKE_PREFIX/usr" ]
then
    for i in bin etc include lib libexec
    do
        ln -s usr/$i "$SNOWFLAKE_PREFIX/$i"
    done
    ln -s bin "$SNOWFLAKE_PREFIX/sbin"
    for i in boot dev home local pkg proc root sys tmp usr var/log/dmesg \
        var/log/sshd var/log/crond var/spool/cron/crontabs
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
cp "$SNOWFLAKE_BASE/config/musl.config.mak" musl-$MUSL_VERSION/config.mak
buildmake musl-$MUSL_VERSION
doinstall '' musl-$MUSL_VERSION DESTDIR="$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr"
rm -rf "$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr/bin" # No musl-gcc needed or wanted
unset PREFIX

# busybox
fetchextract http://busybox.net/downloads/ busybox-$BUSYBOX_VERSION .tar.bz2
patch_source busybox-$BUSYBOX_VERSION
cp "$SNOWFLAKE_BASE/config/busybox.config" busybox-$BUSYBOX_VERSION/.config
buildmake busybox-$BUSYBOX_VERSION LDFLAGS=-static \
    CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc"
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/busybox/$BUSYBOX_VERSION/usr/sbin" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/busybox/$BUSYBOX_VERSION/usr"
    ln -s bin "$SNOWFLAKE_PREFIX/pkg/busybox/$BUSYBOX_VERSION/usr/sbin"
fi
doinstall '' busybox-$BUSYBOX_VERSION LDFLAGS=-static \
    CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc" \
    CONFIG_PREFIX="$SNOWFLAKE_PREFIX/pkg/busybox/$BUSYBOX_VERSION/usr"

# quicklink
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/quicklink/$QUICKLINK_VERSION/usr/bin/snowflake-quicklink" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/quicklink/$QUICKLINK_VERSION/usr/bin"
    cp "$SNOWFLAKE_BASE/snowflake-quicklink" "$SNOWFLAKE_PREFIX/pkg/quicklink/$QUICKLINK_VERSION/usr/bin/"
    echo busybox > "$SNOWFLAKE_PREFIX/pkg/quicklink/$QUICKLINK_VERSION/deps"
fi

# usrview
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/usrview/$USRVIEW_VERSION/usr/bin/usrview" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/usrview/$USRVIEW_VERSION/usr/bin"
    pushd "$SNOWFLAKE_BASE/../usrview"
    make clean
    make CC="$TRIPLE-gcc -static -s"
    popd
    cp "$SNOWFLAKE_BASE/../usrview/usrview" "$SNOWFLAKE_PREFIX/pkg/usrview/$USRVIEW_VERSION/usr/bin/"
fi

# pkgresolve
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/pkgresolve/$PKGRESOLVE_VERSION/usr/bin/with" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/pkgresolve/$PKGRESOLVE_VERSION/usr/bin"
    pushd "$SNOWFLAKE_BASE/../pkgresolve"
    make clean
    make CC="$TRIPLE-gcc -static -s"
    popd
    cp "$SNOWFLAKE_BASE/../pkgresolve/pkgresolve" "$SNOWFLAKE_PREFIX/pkg/pkgresolve/$PKGRESOLVE_VERSION/usr/bin/"
    ln -s pkgresolve "$SNOWFLAKE_PREFIX/pkg/pkgresolve/$PKGRESOLVE_VERSION/usr/bin/with"
    echo usrview > "$SNOWFLAKE_PREFIX/pkg/pkgresolve/$PKGRESOLVE_VERSION/deps"
fi

# core files
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/core/1.0/usr/etc" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/core/1.0/usr/etc"
    cp -R "$SNOWFLAKE_BASE/etc" "$SNOWFLAKE_PREFIX/pkg/core/1.0/"
    pushd "$SNOWFLAKE_BASE/etc"
    for i in *
    do
        ln -s /pkg/core/1.0/etc/$i "$SNOWFLAKE_PREFIX/pkg/core/1.0/usr/etc/$i"
    done
    popd
    ln -s /local "$SNOWFLAKE_PREFIX/pkg/core/1.0/usr/local"
    ln -s bin "$SNOWFLAKE_PREFIX/pkg/core/1.0/usr/sbin"
fi

# minimal and default metapackages
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/minimal/1.0/usr" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/minimal/1.0/usr"
    echo musl busybox pkgresolve > "$SNOWFLAKE_PREFIX/pkg/minimal/1.0/deps"
fi
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/default/1.0/usr" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/default/1.0/usr"
    echo minimal > "$SNOWFLAKE_PREFIX/pkg/default/1.0/deps"
fi

# binutils
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/binutils/ binutils-$BINUTILS_VERSION .tar.bz2
nolib64 "$SNOWFLAKE_PREFIX/pkg/binutils/$BINUTILS_VERSION/usr"
MAKEFLAGS="$MAKEFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/binutils/$BINUTILS_VERSION" \
    buildinstall root binutils-$BINUTILS_VERSION --host=$TRIPLE --target=$TRIPLE \
        --disable-werror
nolib64end "$SNOWFLAKE_PREFIX/pkg/binutils/$BINUTILS_VERSION/usr"
echo musl > "$SNOWFLAKE_PREFIX/pkg/binutils/$BINUTILS_VERSION/deps"
unset PREFIX

# gcc
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/ gcc-$GCC_VERSION .tar.bz2
nolib64 "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr"
MAKEFLAGS="$MAKEFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION" \
    buildinstall root gcc-$GCC_VERSION --host=$TRIPLE --target=$TRIPLE \
    --enable-languages=c --disable-multilib --disable-libmudflap
nolib64end "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr"
echo musl binutils > "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/deps"
unset PREFIX

# un"fix" headers
rm -rf "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr/lib/gcc/$TRIPLE"/*/include-fixed/

# kernel
gitfetchextract 'git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-linux.git' $LINUX_VERSION aufs3-linux-$LINUX_VERSION
cp "$SNOWFLAKE_BASE/config/linux.config" aufs3-linux-$LINUX_VERSION/.config
buildmake aufs3-linux-$LINUX_VERSION ARCH=$LINUX_ARCH
if [ ! -e "$SNOWFLAKE_PREFIX/boot/vmlinuz" ]
then
    cp -L aufs3-linux-$LINUX_VERSION/arch/$LINUX_ARCH/boot/*zImage "$SNOWFLAKE_PREFIX/boot/vmlinuz"
fi
if [ ! -e "$SNOWFLAKE_PREFIX/boot/extlinux.conf" ]
then
    cp "$SNOWFLAKE_BASE/config/extlinux.conf" "$SNOWFLAKE_PREFIX/boot/"
fi

# make usrview setuid-root
$SUDO chown 0:0 "$SNOWFLAKE_PREFIX/pkg/usrview/$USRVIEW_VERSION/usr/bin/usrview"
$SUDO chmod 4755 "$SNOWFLAKE_PREFIX/pkg/usrview/$USRVIEW_VERSION/usr/bin/usrview"

# make everything mountable
for pkg in core/1.0 minimal/1.0 default/1.0 musl/$MUSL_VERSION \
    busybox/$BUSYBOX_VERSION quicklink/$QUICKLINK_VERSION \
    usrview/$USRVIEW_VERSION pkgresolve/$PKGRESOLVE_VERSION \
    binutils/$BINUTILS_VERSION gcc/$GCC_VERSION
do
    $SUDO touch "$SNOWFLAKE_PREFIX/pkg/$pkg/usr/.usr_ok"
done

# actually perform the linking
$SUDO chroot "$SNOWFLAKE_PREFIX" /pkg/busybox/$BUSYBOX_VERSION/usr/bin/sh \
    /pkg/quicklink/$QUICKLINK_VERSION/usr/bin/snowflake-quicklink
