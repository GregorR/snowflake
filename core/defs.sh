# Definitions for build scripts
# 
# Copyright (C) 2012, 2013 Gregor Richards
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

ORIGPWD="$PWD"
cd "$SNOWFLAKE_BASE"
SNOWFLAKE_BASE="$PWD"
export SNOWFLAKE_BASE
cd "$ORIGPWD"
unset ORIGPWD

if [ ! "$MUSL_CC_BASE" ]
then
    MUSL_CC_BASE="$SNOWFLAKE_BASE/../musl-cross"
fi

# Versions of things (do this before config.sh so they can be config'd)
BUSYBOX_VERSION=1.20.2
GAWK_VERSION=4.0.1
GMP_VERSION=5.0.5
LINUX_VERSION=e96cb6825a897a1f90d0e258c77048ee622cd9b6
PKGRESOLVE_VERSION=0.1
PKGSRC_VERSION=2013Q2
QUICKLINK_VERSION=0.1
SNPS_VERSION=0.1
USRVIEW_VERSION=0.1

# Include musl-cross's defs.sh
. "$MUSL_CC_BASE/defs.sh"

# Don't allow in-directory builds
if [ -e buildroot.sh ]
then
    echo 'Please copy config.sh to a different directory and run this script from there.'
    exit 1
fi

# Try to figure out whether we're native
if [ -z "$NATIVE" ]
then
    if [ "`gcc -dumpmachine 2> /dev/null | grep linux-musl`" ]
    then
        NATIVE=yes
    else
        NATIVE=no
    fi
fi

# Use our own defconfigs
case "$LINUX_ARCH" in
    arm)
        LINUX_DEFCONFIG="vexpress_defconfig"
        ;;

    mips)
        LINUX_DEFCONFIG="malta_defconfig"
        ;;

    powerpc)
        LINUX_DEFCONFIG="pmac32_defconfig"
        ;;
esac


nolib64() {
    if [ ! -e "$1"/lib64 ]
    then
        mkdir -p "$1"/lib
        ln -s lib "$1"/lib64
    fi
}

nolib64end() {
    rm -f "$1"/lib64
}
