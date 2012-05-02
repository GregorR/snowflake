#!/bin/bash -x
# Build a cross-prefix without a cross compiler
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

if [ "$SNOWFLAKE_EXPERIMENTAL" != "yes" ]
then
    echo 'buildcross.sh is currently nonworking.'
fi

if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
fi

[ -z "$CC" ] && CC=gcc
[ -z "$AR" ] && AR=ar
[ -z "$RANLIB" ] && RANLIB=ranlib
[ -z "$OBJCOPY" ] && OBJCOPY=objcopy

# Fail on any command failing:
set -e

. "$SNOWFLAKE_BASE"/defs.sh

# Switch to the CC prefix for all of this
PREFIX="$CC_PREFIX"

# linux headers
fetchextract http://www.kernel.org/pub/linux/kernel/v3.0/ linux-$LINUX_HEADERS_VERSION .tar.bz2
cp "$SNOWFLAKE_BASE/config/linux.config" linux-$LINUX_HEADERS_VERSION/.config
if [ ! -e linux-$LINUX_HEADERS_VERSION/installedheaders ]
then
    pushd linux-$LINUX_HEADERS_VERSION
    make headers_install ARCH=$LINUX_ARCH INSTALL_HDR_PATH="$CC_PREFIX/$TRIPLE"
    touch installedheaders
    popd
fi

# musl in CC prefix
PREFIX="$CC_PREFIX/$TRIPLE"
export PREFIX
fetchextract http://www.etalabs.net/musl/releases/ musl-$MUSL_VERSION .tar.gz
cp "$SNOWFLAKE_BASE/config/musl.config.mak" musl-$MUSL_VERSION/config.mak
buildmake musl-$MUSL_VERSION CC="$CC" AR="$AR" RANLIB="$RANLIB" OBJCOPY="$OBJCOPY"
doinstall '' musl-$MUSL_VERSION CC="$CC" AR="$AR" RANLIB="$RANLIB" OBJCOPY="$OBJCOPY"
unset PREFIX
PREFIX="$CC_PREFIX"

# $TRIPLE-tools
if [ ! -e "$CC_PREFIX/bin/$TRIPLE-gcc" ]
then
    # first off, make a g++ version of musl-gcc
    if [ ! -e "$CC_PREFIX/$TRIPLE/bin/musl-g++" ]
    then
        sed 's/gcc/g++/' < "$CC_PREFIX/$TRIPLE/bin/musl-gcc" > "$CC_PREFIX/$TRIPLE/bin/musl-g++"
        chmod 0755 "$CC_PREFIX/$TRIPLE/bin/musl-g++"
    fi

    # then link in the tools
    mkdir -p "$CC_PREFIX/bin"
    ln -s ../$TRIPLE/bin/musl-gcc "$CC_PREFIX/bin/$TRIPLE-gcc"
    ln -s ../$TRIPLE/bin/musl-g++ "$CC_PREFIX/bin/$TRIPLE-g++"

    for t in ar as ld nm ranlib
    do
        ln -s "`which $t`" "$CC_PREFIX/bin/$TRIPLE-$t"
    done
fi

# some components of the host gcc which are necessary for cross-building the guest gcc
if [ ! -e "$CC_PREFIX/$TRIPLE/include/unwind.h" ]
then
    UNWIND=`echo '#include <unwind.h>' | gcc -x c -E - | grep '# 1 ".*unwind\.h"' | cut -d' ' -f3 | sed 's/^"// ; s/"$//'`
    cp "$UNWIND" "$CC_PREFIX/$TRIPLE/include/unwind.h"
    unset UNWIND
fi
