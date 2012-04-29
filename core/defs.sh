if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
fi
export SNOWFLAKE_BASE

if [ ! "$SRCDIR" ]
then
    SRCDIR="$SNOWFLAKE_BASE"
fi

if [ ! -e "$SNOWFLAKE_BASE/config.sh" ]
then
    echo 'Create a config.sh file.'
    exit 1
fi

. "$SNOWFLAKE_BASE"/config.sh

PATH="$CC_PREFIX/bin:$PATH"
export PATH
export TRIPLE # Needed by musl build

# Don't need sudo if we're root
if [ "`id -u`" = "0" ]
then
    SUDO=
fi

case "$ARCH" in
    x86_64) MUSL_ARCH=x86_64 ;;
    *) MUSL_ARCH=i386 ;;
esac
export MUSL_ARCH

die() {
    echo "$@"
    exit 1
}

fetch() {
    if [ ! -e "$SRCDIR/$2" ]
    then
        wget "$1""$2" -O "$SRCDIR/$2" || ( rm -f "$SRCDIR/$2" && return 1 )
    fi
    return 0
}

extract() {
    if [ ! -e "$2" ]
    then
        tar xf "$SRCDIR/$1" ||
            tar jxf "$SRCDIR/$1" ||
            tar zxf "$SRCDIR/$1"
    fi
}

fetchextract() {
    fetch "$1" "$2""$3"
    extract "$2""$3" "$2"
}

patch_source() {
    BD="$1"

    pushd "$BD" || die "Failed to pushd $BD"

    if [ -e "$SRCDIR/$BD"-musl.diff -a ! -e patched ]
    then
        patch -p1 < "$SRCDIR/$BD"-musl.diff || die "Failed to patch $BD"
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
    mkdir -p "$1"/lib
    ln -s lib "$1"/lib64
}

nolib64end() {
    rm -f "$1"/lib64
}
