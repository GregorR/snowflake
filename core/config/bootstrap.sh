#!/bin/sh
set -e

# make
cd make-MAKE_VERSION
with gcc -q make/MAKE_VERSION -- env CFLAGS='-O2 -g -D__BEOS__' \
    sh -c './configure --prefix=/usr && ./build.sh && ./make && ./make install'
cd ..

# gawk
cd gawk-GAWK_VERSION
with gcc make -q gawk/GAWK_VERSION -- sh -c './configure --prefix=/usr && make && make install && ln -fs gawk /usr/bin/awk'
cd ..

# pkgsrc
if [ -e pkgsrc ] ; then mv pkgsrc /var/ ; fi
if [ -e /var/pkgsrc ]
then
    cd /var/pkgsrc/bootstrap
    with gcc make gawk -q pkgsrc/PKGSRC_VERSION -- env \
        CC='gcc -D_GNU_SOURCE -D_BSD_SOURCE' USE_NATIVE_GCC=yes NOGCCERROR=yes \
        ./bootstrap --prefix=/usr --varbase=/var
fi
