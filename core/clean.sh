#!/bin/bash -x
# Clean up after ourselves
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

. "$SNOWFLAKE_BASE"/defs.sh

rm -rf \
    binutils-$BINUTILS_VERSION/ busybox-$BUSYBOX_VERSION/ mpc-$MPC_VERSION/ \
    mpfr-$MPFR_VERSION/ gcc-$GCC_VERSION/ gmp-$GMP_VERSION/ \
    aufs3-linux-$LINUX_VERSION/ musl-$MUSL_VERSION/

if [ -e root ]
then
    $SUDO rm -rf root/
fi
