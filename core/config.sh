SNOWFLAKE_PREFIX="$PWD/root"
ARCH=`uname -m`
TRIPLE=$ARCH-pc-linux-musl
CC_PREFIX=/opt/cross/$TRIPLE
MAKEFLAGS=-j8
SUDO=sudo
WITH_PKGSRC=no
