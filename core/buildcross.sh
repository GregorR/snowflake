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

if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
fi

if [ -z "$CC" ]
then
    CC=gcc
fi
if [ -z "$AR" ]
then
    AR=ar
fi
if [ -z "$RANLIB" ]
then
    RANLIB=ranlib
fi

# Fail on any command failing:
set -e

. "$SNOWFLAKE_BASE"/defs.sh

# Switch to the CC prefix for all of this
PREFIX="$CC_PREFIX"

# linux headers
gitfetchextract 'git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-linux.git' $LINUX_VERSION aufs3-linux-$LINUX_VERSION
cp linux.config aufs3-linux-$LINUX_VERSION/.config
if [ ! -e aufs3-linux-$LINUX_VERSION/installedheaders ]
then
    pushd aufs3-linux-$LINUX_VERSION
    make headers_install INSTALL_HDR_PATH="$CC_PREFIX/$TRIPLE"
    touch installedheaders
    popd
fi

# musl in CC prefix
PREFIX="$CC_PREFIX/$TRIPLE"
export PREFIX
fetchextract http://www.etalabs.net/musl/releases/ musl-$MUSL_VERSION .tar.gz
cp musl.config.mak musl-$MUSL_VERSION/config.mak
buildmake musl-$MUSL_VERSION CC="$CC" AR="$AR" RANLIB="$RANLIB"
doinstall '' musl-$MUSL_VERSION CC="$CC" AR="$AR" RANLIB="$RANLIB"
unset PREFIX
PREFIX="$CC_PREFIX"

# $TRIPLE-tools
if [ ! -e "$CC_PREFIX/bin/$TRIPLE-gcc" ]
then
    mkdir -p "$CC_PREFIX/bin"
    ln -s ../$TRIPLE/bin/musl-gcc "$CC_PREFIX/bin/$TRIPLE-gcc"

    for t in ar as ranlib ld
    do
        ln -s "`which $t`" "$CC_PREFIX/bin/$TRIPLE-$t"
    done
fi
