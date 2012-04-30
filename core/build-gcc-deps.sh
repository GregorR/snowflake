#!/bin/bash -x
# Build deps for GCC
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

# Switch to the CC prefix for all of this
PREFIX="$CC_PREFIX/$TRIPLE"

# GMP
fetchextract ftp://ftp.gmplib.org/pub/gmp-$GMP_VERSION/ gmp-$GMP_VERSION .tar.bz2
cp -f "$SNOWFLAKE_BASE/config/config.sub" gmp-$GMP_VERSION/configfsf.sub
buildinstall '' gmp-$GMP_VERSION --host="$TRIPLE" --enable-static --disable-shared

# MPFR
fetchextract http://www.mpfr.org/mpfr-current/ mpfr-$MPFR_VERSION .tar.bz2
cp -f "$SNOWFLAKE_BASE/config/config.sub" mpfr-$MPFR_VERSION/config.sub
buildinstall '' mpfr-$MPFR_VERSION --host="$TRIPLE" --enable-static --disable-shared CC="$TRIPLE-gcc"

# MPC
fetchextract http://www.multiprecision.org/mpc/download/ mpc-$MPC_VERSION .tar.gz
cp -f "$SNOWFLAKE_BASE/config/config.sub" mpc-$MPC_VERSION/config.sub
buildinstall '' mpc-$MPC_VERSION --host="$TRIPLE" --enable-static --disable-shared
