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

# linux headers
fetchextract http://www.kernel.org/pub/linux/kernel/v3.0/ linux-$LINUX_HEADERS_VERSION .tar.bz2
if [ ! -e linux-$LINUX_HEADERS_VERSION/configured ]
then
    pushd linux-$LINUX_HEADERS_VERSION
    make defconfig ARCH=$LINUX_ARCH
    cat "$SNOWFLAKE_BASE/config/linux.config" >> .config
    yes '' | make oldconfig ARCH=$LINUX_ARCH
    touch configured
    popd
fi
if [ ! -e linux-$LINUX_HEADERS_VERSION/installedrootheaders ]
then
    pushd linux-$LINUX_HEADERS_VERSION
    make headers_install ARCH=$LINUX_ARCH INSTALL_HDR_PATH="$SNOWFLAKE_PREFIX/pkg/linux-headers/$LINUX_HEADERS_VERSION/usr"
    touch installedrootheaders
    popd
fi

# musl
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr/lib/libc.so" ]
then
    rm -f musl-$MUSL_VERSION/installed # Force it to reinstall
fi
PREFIX="/"
export PREFIX
fetchextract http://www.etalabs.net/musl/releases/ musl-$MUSL_VERSION .tar.gz
CC="$TRIPLE-gcc" DESTDIR="$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr" \
    buildinstall '' musl-$MUSL_VERSION
rm -rf "$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/usr/bin" # No musl-gcc needed or wanted
echo linux-headers > "$SNOWFLAKE_PREFIX/pkg/musl/$MUSL_VERSION/deps"
unset PREFIX
PREFIX="$CC_PREFIX"

# fake ldd (remove this when musl has its own)
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/ldd/$LDD_VERSION/usr/bin/ldd" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/ldd/$LDD_VERSION/usr/bin"
    cp "$SNOWFLAKE_BASE/ldd" "$SNOWFLAKE_PREFIX/pkg/ldd/$LDD_VERSION/usr/bin/"
    chmod 0755 "$SNOWFLAKE_PREFIX/pkg/ldd/$LDD_VERSION/usr/bin/ldd"
fi

# busybox
fetchextract http://busybox.net/downloads/ busybox-$BUSYBOX_VERSION .tar.bz2
patch_source busybox-$BUSYBOX_VERSION
cp "$SNOWFLAKE_BASE/config/busybox.config" busybox-$BUSYBOX_VERSION/.config
buildmake busybox-$BUSYBOX_VERSION LDFLAGS=-static \
    CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc" STRIP="$TRIPLE-strip"
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
    echo musl libgcc busybox pkgresolve ldd > "$SNOWFLAKE_PREFIX/pkg/minimal/1.0/deps"
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
unset PREFIX

# gcc
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/ gcc-$GCC_VERSION .tar.bz2
nolib64 "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr"
MAKEFLAGS="$MAKEFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION" \
    buildinstall root gcc-$GCC_VERSION --host=$TRIPLE --target=$TRIPLE \
    --enable-languages=c,c++ --disable-multilib --disable-libmudflap
nolib64end "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr"
# get the libs into their own path
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/libgcc/$GCC_VERSION/usr/lib" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/libgcc/$GCC_VERSION/usr/lib"
    mv "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr/lib"/*.so.* "$SNOWFLAKE_PREFIX/pkg/libgcc/$GCC_VERSION/usr/lib/"
fi
echo binutils > "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/deps"
unset PREFIX

# un"fix" headers
if [ -e "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr/lib/gcc/$TRIPLE"/*/include-fixed/ ]
then
    pushd "$SNOWFLAKE_PREFIX/pkg/gcc/$GCC_VERSION/usr/lib/gcc/$TRIPLE"/*/include-fixed/
    for file in *
    do
        [ "$file" != "limits.h" -a "$file" != "syslimits.h" ] && rm -rf $file
    done
    popd
fi

# kernel
gitfetchextract 'git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-linux.git' $LINUX_VERSION aufs3-linux-$LINUX_VERSION
if [ ! -e aufs3-linux-$LINUX_VERSION/configured ]
then
    pushd aufs3-linux-$LINUX_VERSION
    EXTRA_FLAGS=
    if [ "$LINUX_ARCH" = "arm" ]
    then
        EXTRA_FLAGS="KBUILD_DEFCONFIG=vexpress_defconfig"
    fi
    make defconfig ARCH=$LINUX_ARCH $EXTRA_FLAGS
    unset EXTRA_FLAGS
    cat "$SNOWFLAKE_BASE/config/linux.config" >> .config
    yes '' | make oldconfig ARCH=$LINUX_ARCH
    touch configured
    popd
fi
buildmake aufs3-linux-$LINUX_VERSION ARCH=$LINUX_ARCH CROSS_COMPILE=$TRIPLE-
if [ ! -e "$SNOWFLAKE_PREFIX/boot/vmlinuz" ]
then
    cp -L aufs3-linux-$LINUX_VERSION/arch/$LINUX_ARCH/boot/*zImage "$SNOWFLAKE_PREFIX/boot/vmlinuz"
fi
if [ ! -e "$SNOWFLAKE_PREFIX/boot/extlinux.conf" ]
then
    cp "$SNOWFLAKE_BASE/config/extlinux.conf" "$SNOWFLAKE_PREFIX/boot/"
fi

# a few things distributed as source to be built later
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/sed/$SED_VERSION/usr" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/src"
    fetchextract http://ftp.gnu.org/gnu/make/ make-$MAKE_VERSION .tar.bz2
    fetchextract http://ftp.gnu.org/gnu/sed/ sed-$SED_VERSION .tar.bz2
    fetchextract http://ftp.gnu.org/gnu/gawk/ gawk-$GAWK_VERSION .tar.xz
    #fetchextract http://ftp.gnu.org/pub/gnu/ncurses/ ncurses-$NCURSES_VERSION .tar.gz
    PKGSRC=
    if [ "$WITH_PKGSRC" = "yes" ]
    then
        PKGSRC=pkgsrc
        fetchextract ftp://ftp.netbsd.org/pub/pkgsrc/pkgsrc-$PKGSRC_VERSION/ pkgsrc .tar.gz
        patch_source pkgsrc
    fi
    #for pkg in make-$MAKE_VERSION sed-$SED_VERSION gawk-$GAWK_VERSION ncurses-$NCURSES_VERSION $PKGSRC
    for pkg in make-$MAKE_VERSION sed-$SED_VERSION gawk-$GAWK_VERSION $PKGSRC
    do
        if [ ! -e "$SNOWFLAKE_PREFIX/src/$pkg" ]
        then
            cp -a $pkg "$SNOWFLAKE_PREFIX/src/"
        fi
    done
    #cp "$SNOWFLAKE_BASE/config/ncurses-fallback.c" "$SNOWFLAKE_PREFIX/src/ncurses-$NCURSES_VERSION/ncurses/fallback.c"
    if [ ! -e "$SNOWFLAKE_PREFIX/src/bootstrap.sh" ]
    then
        sed 's/MAKE_VERSION/'$MAKE_VERSION'/g ; s/SED_VERSION/'$SED_VERSION'/ ;
        s/GAWK_VERSION/'$GAWK_VERSION'/g ; s/NCURSES_VERSION/'$NCURSES_VERSION'/g ;
        s/PKGSRC_VERSION/'$PKGSRC_VERSION'/g' \
            "$SNOWFLAKE_BASE/config/bootstrap.sh" > "$SNOWFLAKE_PREFIX/src/bootstrap.sh"
        chmod 0755 "$SNOWFLAKE_PREFIX/src/bootstrap.sh"
    fi
fi

# helpers for pkgsrc
if [ "$WITH_PKGSRC" = "yes" -a ! -e "$SNOWFLAKE_PREFIX/pkg/snps/$SNPS_VERSION/usr/bin/snps-setenv" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/snps/$SNPS_VERSION/usr/bin"
    for i in snps-clean snps-pkgsrc-install snps-setenv snps-update-tools-list
    do
        cp "$SNOWFLAKE_BASE/$i" "$SNOWFLAKE_PREFIX/pkg/snps/$SNPS_VERSION/usr/bin/"
    done
    chmod 0755 "$SNOWFLAKE_PREFIX/pkg/snps/$SNPS_VERSION/usr/bin"/*
fi

# make usrview setuid-root
$SUDO chown 0:0 "$SNOWFLAKE_PREFIX/pkg/usrview/$USRVIEW_VERSION/usr/bin/usrview"
$SUDO chmod 4755 "$SNOWFLAKE_PREFIX/pkg/usrview/$USRVIEW_VERSION/usr/bin/usrview"

# make everything mountable
for pkg in core/1.0 minimal/1.0 default/1.0 \
    linux-headers/$LINUX_HEADERS_VERSION musl/$MUSL_VERSION \
    ldd/$LDD_VERSION \
    busybox/$BUSYBOX_VERSION quicklink/$QUICKLINK_VERSION \
    usrview/$USRVIEW_VERSION pkgresolve/$PKGRESOLVE_VERSION \
    binutils/$BINUTILS_VERSION gcc/$GCC_VERSION libgcc/$GCC_VERSION
do
    $SUDO touch "$SNOWFLAKE_PREFIX/pkg/$pkg/usr/.usr_ok"
done
if [ "$WITH_PKGSRC" = "yes" ]
then
    $SUDO touch "$SNOWFLAKE_PREFIX/pkg/snps/$SNPS_VERSION/usr/.usr_ok"
fi

# actually perform the linking (do this in multiple steps so we can cross-setup)
echo '#!/pkg/busybox/'$BUSYBOX_VERSION'/usr/bin/sh
exec /pkg/busybox/'$BUSYBOX_VERSION'/usr/bin/sh /pkg/quicklink/'$QUICKLINK_VERSION'/usr/bin/snowflake-quicklink' \
    > "$SNOWFLAKE_PREFIX/setup_usr.sh"
chmod a+x "$SNOWFLAKE_PREFIX/setup_usr.sh"
$SUDO chroot "$SNOWFLAKE_PREFIX" /setup_usr.sh
rm -f "$SNOWFLAKE_PREFIX/setup_usr.sh"
