#!/bin/sh
set -e

# make
cd /src/make-MAKE_VERSION
with gcc -q make/MAKE_VERSION -- env CFLAGS='-O2 -g -D__BEOS__' \
    sh -c './configure --prefix=/usr && ./build.sh && ./make && ./make install'
cd ..

# sed
cd /src/sed-SED_VERSION
with gcc make -q sed/SED_VERSION -- sh -c './configure --prefix=/usr && make && make install'

# gawk
cd /src/gawk-GAWK_VERSION
with gcc make -q gawk/GAWK_VERSION -- sh -c './configure --prefix=/usr && make && make install && ln -fs gawk /usr/bin/awk'

# ncurses
#cd /src/ncurses-NCURSES_VERSION
#with gcc make sed gawk -q ncurses/b.NCURSES_VERSION.static -- sh -c '
#CC="gcc -static -D_GNU_SOURCE" ./configure \
#    --with-normal \
#    --enable-sigwinch --with-fallbacks="linux vt100 xterm xterm256-color" \
#    --prefix=/usr \
#    --disable-nls --without-dlsym --without-cxx-binding < /dev/ptmx &&
#make && make install'

# pkgsrc
[ -e /src/pkgsrc ] && mv /src/pkgsrc /var/
if [ -e /var/pkgsrc ]
then
    cd /var/pkgsrc/bootstrap
    with gcc make sed gawk -q pkgsrc/PKGSRC_VERSION -- env \
        CC='gcc -D_GNU_SOURCE -D_BSD_SOURCE' USE_NATIVE_GCC=yes NOGCCERROR=yes \
        ./bootstrap --prefix=/usr --varbase=/var

    # we inject a dependency on gzip, as some packages require gzip (and not
    # busybox gzip) to extract due to .Z files. This is harmless if gzip
    # doesn't exist
    echo snps gcc sed gawk gzip > /pkg/pkgsrc/PKGSRC_VERSION/deps

    # snowflake-ize it
    echo '
# musl is very ... conservative about what symbols it exposes    
CFLAGS+=-D_GNU_SOURCE -D_BSD_SOURCE

# snps-setenv cleverly translates pkgsrc packages to Snowflake usrviews
SETENV=snps-setenv "${PKGNAME}" "${DEPENDS}" "${BUILD_DEPENDS} ${BOOTSTRAP_DEPENDS}" "${USE_TOOLS}"

# Circular depends if you don'\''t have builtin things
FETCH_USING=fetch
PKG_OPTIONS.groff=-groff-docs -x11

# pkgsrc doesn'\''t know how to build a musl GCC
USE_NATIVE_GCC=yes
NOGCCERROR=yes

# Using /usr as pkgsrc'\''s install prefix breaks some tests, so insist that these are builtin
IS_BUILTIN.dl=yes
IS_BUILTIN.pthread=yes
' >> \
        /pkg/pkgsrc/PKGSRC_VERSION/usr/etc/mk.conf
    echo -e '\tsnps-pkgsrc-install' >> /var/pkgsrc/mk/pkgformat/pkg/package.mk
fi

# delete the source
cd /
rm -rf /src/
