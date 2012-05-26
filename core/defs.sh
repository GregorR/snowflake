# Definitions for build scripts
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
export SNOWFLAKE_BASE

if [ ! "$SRCDIR" ]
then
    SRCDIR="$SNOWFLAKE_BASE"
fi

if [ ! -e config.sh ]
then
    echo 'Create a config.sh file.'
    exit 1
fi

# Versions of things (do this before config.sh so they can be config'd)
AUFS_UTIL_VERSION=cc453fadac6d61dc5d14d3c905f72d01d5011049
BINUTILS_VERSION=2.22
BUSYBOX_VERSION=1.19.4
GAWK_VERSION=4.0.1
GCC_VERSION=4.7.0
GLIBC_VERSION=2.15
GMP_VERSION=5.0.4
LDD_VERSION=0.1
LINUX_HEADERS_VERSION=3.2.15
LINUX_VERSION=6ee00da3eefd493456259fe774a74dfb12c49152
MAKE_VERSION=3.82
MPC_VERSION=0.9
MPFR_VERSION=3.1.0
NCURSES_VERSION=5.9
PKGRESOLVE_VERSION=0.1
PKGSRC_VERSION=2012Q1
QUICKLINK_VERSION=0.1
SED_VERSION=4.2.1
SNPS_VERSION=0.1
USRVIEW_VERSION=0.1

MUSL_DEFAULT_VERSION=0.9.9
MUSL_GIT_VERSION=8b4c232efe182f4a9c8c52c5638af8fec92987bf
MUSL_VERSION="$MUSL_DEFAULT_VERSION"
MUSL_GIT=no

. config.sh

# Use musl git version on ARM, as 0.9.0 isn't new enough
if [ "$ARCH" = "arm" -a "$MUSL_VERSION" = "$MUSL_DEFAULT_VERSION" ]
then
    MUSL_VERSION="$MUSL_GIT_VERSION"
    MUSL_GIT=yes
fi

PATH="$CC_PREFIX/bin:$PATH"
export PATH
export TRIPLE # Needed by musl build

# Don't need sudo if we're root
if [ "`id -u`" = "0" ]
then
    SUDO=
fi

case "$ARCH" in
    i*86) LINUX_ARCH=i386 ;;
    *) LINUX_ARCH="$ARCH" ;;
esac
export LINUX_ARCH

die() {
    echo "$@"
    exit 1
}

fetch() {
    if [ ! -e "$SRCDIR/tarballs/$2" ]
    then
        wget "$1""$2" -O "$SRCDIR/tarballs/$2" || ( rm -f "$SRCDIR/tarballs/$2" && return 1 )
    fi
    return 0
}

extract() {
    if [ ! -e "$2" ]
    then
        tar xf "$SRCDIR/tarballs/$1" ||
            tar Jxf "$SRCDIR/tarballs/$1" ||
            tar jxf "$SRCDIR/tarballs/$1" ||
            tar zxf "$SRCDIR/tarballs/$1"
    fi
}

fetchextract() {
    fetch "$1" "$2""$3"
    extract "$2""$3" "$2"
}

gitfetchextract() {
    if [ ! -e "$SRCDIR/tarballs/$3".tar.gz ]
    then
        git archive --format=tar --remote="$1" "$2" | \
            gzip -c > "$SRCDIR/tarballs/$3".tar.gz || die "Failed to fetch $3-$2"
    fi
    if [ ! -e "$3/extracted" ]
    then
        mkdir -p "$3"
        pushd "$3" || die "Failed to pushd $3"
        extract "$3".tar.gz extracted
        touch extracted
        popd
    fi
}

muslfetchextract() {
    if [ "$MUSL_GIT" = "yes" ]
    then
        gitfetchextract 'git://repo.or.cz/musl.git' $MUSL_VERSION musl-$MUSL_VERSION
    else
        fetchextract http://www.etalabs.net/musl/releases/ musl-$MUSL_VERSION .tar.gz
    fi
}

patch_source() {
    BD="$1"

    pushd "$BD" || die "Failed to pushd $BD"

    if [ -e "$SRCDIR/patches/$BD"-musl.diff -a ! -e patched ]
    then
        patch -p1 < "$SRCDIR/patches/$BD"-musl.diff || die "Failed to patch $BD"
        touch patched
    fi
    popd
}

build() {
    BP="$1"
    BD="$2"
    CF="./configure"
    BUILT="$PWD/$BD/built$BP"
    shift; shift

    if [ ! -e "$BUILT" ]
    then
        patch_source "$BD"

        pushd "$BD" || die "Failed to pushd $BD"

        if [ -e config.cache.microcosm ]
        then
            cp -f config.cache.microcosm config.cache
        fi

        if [ "$BP" ]
        then
            mkdir -p build"$BP"
            cd build"$BP" || die "Failed to cd to build dir for $BD $BP"
            CF="../configure"
        fi
        ( $CF --prefix="$PREFIX" "$@" &&
            make $MAKEFLAGS &&
            touch "$BUILT" ) ||
            die "Failed to build $BD"

        popd
    fi
}

buildmake() {
    BD="$1"
    BUILT="$PWD/$BD/built"
    shift

    if [ ! -e "$BUILT" ]
    then
        pushd "$BD" || die "Failed to pushd $BD"

        if [ -e "$SRCDIR/$BD"-musl.diff -a ! -e patched ]
        then
            patch -p1 < "$SRCDIR/$BD"-musl.diff || die "Failed to patch $BD"
            touch patched
        fi

        ( make "$@" $MAKEFLAGS &&
            touch "$BUILT" ) ||
            die "Failed to build $BD"

        popd
    fi
}

doinstall() {
    BP="$1"
    BD="$2"
    INSTALLED="$PWD/$BD/installed$BP"
    shift; shift

    if [ ! -e "$INSTALLED" ]
    then
        pushd "$BD" || die "Failed to pushd $BD"

        if [ "$BP" ]
        then
            cd build"$BP" || die "Failed to cd build$BP"
        fi

        ( make install "$@" &&
            touch "$INSTALLED" ) ||
            die "Failed to install $BP"

        popd
    fi
}

buildinstall() {
    build "$@"
    doinstall "$1" "$2"
}

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
