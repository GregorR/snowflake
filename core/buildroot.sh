#!/bin/sh
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
    SNOWFLAKE_BASE=`dirname "$0"`
fi

# Fail on any command failing, show commands:
set -ex

MUSL_ROOT_CONFFLAGS=
BINUTILS_ROOT_CONFFLAGS=
GCC_ROOT_CONFFLAGS=
. "$SNOWFLAKE_BASE"/defs.sh

# use SNOWFLAKE_BASE for all builds now
MUSL_CC_BASE="$SNOWFLAKE_BASE"

# base files
mkdir -p "$SNOWFLAKE_PREFIX"
if [ ! -e "$SNOWFLAKE_PREFIX/usr" ]
then
    for i in bin etc include lib libexec
    do
        ln -sf usr/$i "$SNOWFLAKE_PREFIX/$i"
    done
    ln -sf bin "$SNOWFLAKE_PREFIX/sbin"
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
    (
    cd linux-$LINUX_HEADERS_VERSION
    make $LINUX_DEFCONFIG ARCH=$LINUX_ARCH
    cat "$SNOWFLAKE_BASE/config/linux.config" >> .config
    yes '' | make oldconfig ARCH=$LINUX_ARCH
    touch configured
    )
fi
if [ ! -e linux-$LINUX_HEADERS_VERSION/installedrootheaders ]
then
    (
    cd linux-$LINUX_HEADERS_VERSION
    make headers_install ARCH=$LINUX_ARCH INSTALL_HDR_PATH="$SNOWFLAKE_PREFIX/pkg/$TRIPLE/linux-headers/$LINUX_HEADERS_VERSION/usr"
    touch installedrootheaders
    )
fi

# musl
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/lib/libc.a" ]
then
    rm -f musl-$MUSL_VERSION/built musl-$MUSL_VERSION/installed # Force it to reinstall
fi
PREFIX="$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr"
export PREFIX
muslfetchextract
buildinstall '' musl-$MUSL_VERSION \
    --enable-debug CC="$TRIPLE-gcc" $MUSL_ROOT_CONFFLAGS
rm -f "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/bin/musl-gcc" # No musl-gcc needed or wanted
if [ -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/lib/libc.so" ]
then
    [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/lib/ld-musl-$LINUX_ARCH.so.1" ] && \
        ln -s ../lib/libc.so "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/lib/ld-musl-$LINUX_ARCH.so.1"
    if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/bin/ldd" ]
    then
        mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/bin"
        ln -s ../lib/libc.so "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/usr/bin/ldd"
    fi
fi
echo linux-headers > "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/musl/$MUSL_VERSION/deps"
unset PREFIX
PREFIX="$CC_PREFIX"

# busybox
fetchextract http://busybox.net/downloads/ busybox-$BUSYBOX_VERSION .tar.bz2
patch_source busybox-$BUSYBOX_VERSION
if [ ! -e busybox-$BUSYBOX_VERSION/configured ]
then
    (
    cd busybox-$BUSYBOX_VERSION
    cp "$SNOWFLAKE_BASE/config/busybox.config" .config
    yes '' | make LDFLAGS=-static \
        CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc" STRIP="$TRIPLE-strip" \
        oldconfig
    touch configured
    )
fi
buildmake busybox-$BUSYBOX_VERSION LDFLAGS=-static \
    CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc" STRIP="$TRIPLE-strip"
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/busybox/$BUSYBOX_VERSION/usr/sbin" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/busybox/$BUSYBOX_VERSION/usr"
    ln -s bin "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/busybox/$BUSYBOX_VERSION/usr/sbin"
fi
doinstall '' busybox-$BUSYBOX_VERSION LDFLAGS=-static \
    CFLAGS_busybox="-Wl,-z,muldefs" HOSTCC=gcc CC="$TRIPLE-gcc" STRIP="$TRIPLE-strip" \
    CONFIG_PREFIX="$SNOWFLAKE_PREFIX/pkg/$TRIPLE/busybox/$BUSYBOX_VERSION/usr"

# gawk
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/gawk/ gawk-$GAWK_VERSION .tar.xz
cp -f "$SNOWFLAKE_BASE/../musl-cross/extra/config.sub" gawk-$GAWK_VERSION/config.sub
MAKEINSTALLFLAGS="$MAKEINSTALLFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gawk/b.$GAWK_VERSION" \
    CFLAGS="-O2 -g $CFLAGS" buildinstall root gawk-$GAWK_VERSION --host=$TRIPLE
unset PREFIX

# quicklink
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/quicklink/$QUICKLINK_VERSION/usr/bin/snowflake-quicklink" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/quicklink/$QUICKLINK_VERSION/usr/bin"
    cp "$SNOWFLAKE_BASE/snowflake-quicklink" "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/quicklink/$QUICKLINK_VERSION/usr/bin/"
    echo busybox > "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/quicklink/$QUICKLINK_VERSION/deps"
fi

# usrview
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/usrview/$USRVIEW_VERSION/usr/bin/usrview" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/usrview/$USRVIEW_VERSION/usr/bin"
    (
    cd "$SNOWFLAKE_BASE/../usrview"
    make clean
    make CC="$TRIPLE-gcc -static -s"
    )
    cp "$SNOWFLAKE_BASE/../usrview/usrview" "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/usrview/$USRVIEW_VERSION/usr/bin/"
fi

# pkgresolve
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/pkgresolve/$PKGRESOLVE_VERSION/usr/bin/with" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/pkgresolve/$PKGRESOLVE_VERSION/usr/bin"
    (
    cd "$SNOWFLAKE_BASE/../pkgresolve"
    make clean
    make CC="$TRIPLE-gcc -static -s" DEFAULT_CONFIGURATION="\"$TRIPLE\""
    )
    cp "$SNOWFLAKE_BASE/../pkgresolve/pkgresolve" "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/pkgresolve/$PKGRESOLVE_VERSION/usr/bin/"
    ln -s pkgresolve "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/pkgresolve/$PKGRESOLVE_VERSION/usr/bin/with"
    echo usrview > "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/pkgresolve/$PKGRESOLVE_VERSION/deps"
fi

# rename for some g-named things
if [ -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/busybox/$BUSYBOX_VERSION/usr/bin/awk" ]
then
    rm -f "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/busybox/$BUSYBOX_VERSION/usr/bin/awk"
fi
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/grename/0.1/usr/bin/awk" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/grename/0.1/usr/bin"
    for g in make awk
    do
        ln -sf g$g "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/grename/0.1/usr/bin/$g"
    done
fi

# core files
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/core/core/1.0/usr/etc" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/core/core/1.0/usr/etc"
    cp -R "$SNOWFLAKE_BASE/etc" "$SNOWFLAKE_PREFIX/pkg/core/core/1.0/"
    (
    cd "$SNOWFLAKE_BASE/etc"
    for i in *
    do
        ln -s /pkg/core/core/1.0/etc/$i "$SNOWFLAKE_PREFIX/pkg/core/core/1.0/usr/etc/$i"
    done
    )
    ln -s /local "$SNOWFLAKE_PREFIX/pkg/core/core/1.0/usr/local"
    ln -s bin "$SNOWFLAKE_PREFIX/pkg/core/core/1.0/usr/sbin"
fi

# minimal and default metapackages
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/minimal/1.0/usr" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/minimal/1.0/usr"
    echo musl libgcc busybox gawk pkgresolve grename > "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/minimal/1.0/deps"
fi
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/default/1.0/usr" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/default/1.0/usr"
    echo minimal > "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/default/1.0/deps"
fi

# binutils
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/binutils/ binutils-$BINUTILS_VERSION .tar.bz2
nolib64 "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/binutils/$BINUTILS_VERSION/usr"
# FIXME: In musl 0.9.2 this may be fixed, or alternately, may need to change to _GNU_SOURCE
MAKEINSTALLFLAGS="$MAKEINSTALLFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/$TRIPLE/binutils/$BINUTILS_VERSION" \
    CFLAGS="-O2 -g $CFLAGS -D_LARGEFILE64_SOURCE" buildinstall root binutils-$BINUTILS_VERSION --host=$TRIPLE --target=$TRIPLE \
        --disable-werror $BINUTILS_ROOT_CONFFLAGS
nolib64end "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/binutils/$BINUTILS_VERSION/usr"
unset PREFIX

# gcc
PREFIX="/usr"
fetchextract http://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/ gcc-$GCC_VERSION .tar.bz2
nolib64 "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/usr"
MAKEINSTALLFLAGS="$MAKEINSTALLFLAGS DESTDIR=$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION" \
    buildinstall root gcc-$GCC_VERSION --host=$TRIPLE --target=$TRIPLE \
    --enable-languages=$LANGUAGES --disable-multilib --disable-libmudflap \
    $GCC_ROOT_CONFFLAGS
nolib64end "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/usr"
# get the libs into their own path
if [ ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/libgcc/$GCC_VERSION/usr/lib" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/libgcc/$GCC_VERSION/usr/lib"
    [ -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/usr/lib/libgcc_s.so.1" ] && \
        mv "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/usr/lib"/*.so.* "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/libgcc/$GCC_VERSION/usr/lib/"
fi
echo binutils > "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/deps"
unset PREFIX

# un"fix" headers
if [ -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/usr/lib/gcc/$TRIPLE"/*/include-fixed/ ]
then
    (
    cd "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/usr/lib/gcc/$TRIPLE"/*/include-fixed/
    for file in *
    do
        [ "$file" != "limits.h" -a "$file" != "syslimits.h" ] && rm -rf $file
    done
    true
    )
fi
rm -f "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/gcc/$GCC_VERSION/usr/lib/gcc/$TRIPLE"/*/include/stddef.h

# kernel
gitfetchextract 'git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-linux.git' $LINUX_VERSION aufs3-linux-$LINUX_VERSION
if [ ! -e aufs3-linux-$LINUX_VERSION/configured ]
then
    (
    cd aufs3-linux-$LINUX_VERSION
    if [ "$LINUX_ARCH" = "powerpc" ]
    then
        # Needs stddef.h, which is in the stdinc include path on musl
        mf=arch/powerpc/boot/Makefile
        sed 's/-nostdinc//g' $mf > $mf.fix
        mv $mf.fix $mf
        unset mf
    fi
    make $LINUX_DEFCONFIG ARCH=$LINUX_ARCH $EXTRA_FLAGS
    cat "$SNOWFLAKE_BASE/config/linux.config" >> .config
    [ -e "$SNOWFLAKE_BASE/config/$ARCH/linux.config" ] &&
        cat "$SNOWFLAKE_BASE/config/$ARCH/linux.config" >> .config
    yes '' | make oldconfig ARCH=$LINUX_ARCH
    touch configured
    )
fi
buildmake aufs3-linux-$LINUX_VERSION ARCH=$LINUX_ARCH CROSS_COMPILE=$TRIPLE-
if [ ! -e "$SNOWFLAKE_PREFIX/boot/vmlinuz" ]
then
    cp -L aufs3-linux-$LINUX_VERSION/arch/$LINUX_ARCH/boot/*zImage "$SNOWFLAKE_PREFIX/boot/vmlinuz" ||
        cp -L aufs3-linux-$LINUX_VERSION/vmlinux "$SNOWFLAKE_PREFIX/boot/vmlinux"
fi
if [ ! -e "$SNOWFLAKE_PREFIX/boot/extlinux.conf" ]
then
    cp "$SNOWFLAKE_BASE/config/extlinux.conf" "$SNOWFLAKE_PREFIX/boot/"
fi

# pkgsrc will be built within Snowflake
if [ "$WITH_PKGSRC" = "yes" -a ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/pkgsrc/$PKGSRC_VERSION/usr" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/src"
    PKGSRC=pkgsrc
    fetchextract ftp://ftp.netbsd.org/pub/pkgsrc/pkgsrc-$PKGSRC_VERSION/ pkgsrc-$PKGSRC_VERSION .tar.xz
    if [ ! -e "pkgsrc/patched" ]
    then
        (
        cd pkgsrc
        cat "$SNOWFLAKE_BASE/../pkgsrc-patches"/*.diff | patch -p1
        touch patched
        )
    fi
    if [ ! -e "$SNOWFLAKE_PREFIX/src/pkgsrc" ]
    then
        cp -a pkgsrc "$SNOWFLAKE_PREFIX/src/"
    fi
    if [ ! -e "$SNOWFLAKE_PREFIX/src/bootstrap.sh" ]
    then
        sed 's/DEFAULT_CONFIGURATION/'$TRIPLE'/g ;
        s/PKGSRC_VERSION/'$PKGSRC_VERSION'/g' \
            "$SNOWFLAKE_BASE/config/bootstrap.sh" > "$SNOWFLAKE_PREFIX/src/bootstrap.sh"
        chmod 0755 "$SNOWFLAKE_PREFIX/src/bootstrap.sh"
    fi
fi

# helpers for pkgsrc
if [ "$WITH_PKGSRC" = "yes" -a ! -e "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/snps/$SNPS_VERSION/usr/bin/snps-setenv" ]
then
    mkdir -p "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/snps/$SNPS_VERSION/usr/bin"
    for i in snps-clean snps-pkgsrc-install snps-setenv snps-update-tools-list
    do
        cp "$SNOWFLAKE_BASE/snps/$i" "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/snps/$SNPS_VERSION/usr/bin/"
    done
    chmod 0755 "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/snps/$SNPS_VERSION/usr/bin"/*
fi

# make everything mountable
touch "$SNOWFLAKE_PREFIX/pkg/core/core/1.0/usr/.usr_ok"
for pkg in minimal/1.0 default/1.0 \
    grename/0.1 \
    linux-headers/$LINUX_HEADERS_VERSION musl/$MUSL_VERSION \
    busybox/$BUSYBOX_VERSION gawk/b.$GAWK_VERSION quicklink/$QUICKLINK_VERSION \
    usrview/$USRVIEW_VERSION pkgresolve/$PKGRESOLVE_VERSION \
    binutils/$BINUTILS_VERSION gcc/$GCC_VERSION libgcc/$GCC_VERSION
do
    touch "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/$pkg/usr/.usr_ok"
done
if [ "$WITH_PKGSRC" = "yes" ]
then
    touch "$SNOWFLAKE_PREFIX/pkg/$TRIPLE/snps/$SNPS_VERSION/usr/.usr_ok"
fi

# make a script to perform the linking
mkdir -p "$SNOWFLAKE_PREFIX"/usr/bin
echo '#!/pkg/'$TRIPLE'/busybox/'$BUSYBOX_VERSION'/usr/bin/sh
/pkg/'$TRIPLE'/busybox/'$BUSYBOX_VERSION'/usr/bin/sh /pkg/'$TRIPLE'/quicklink/'$QUICKLINK_VERSION'/usr/bin/snowflake-quicklink '$TRIPLE'
/bin/chmod 4755 /pkg/'$TRIPLE'/usrview/'$USRVIEW_VERSION'/usr/bin/usrview
if [ "$$" = "1" ]
then
    /bin/sync
    /bin/reboot -f
fi' \
    > "$SNOWFLAKE_PREFIX/usr/bin/init"
chmod a+x "$SNOWFLAKE_PREFIX/usr/bin/init"
