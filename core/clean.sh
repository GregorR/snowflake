#!/bin/bash -x
# Clean up after ourselves

if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
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
