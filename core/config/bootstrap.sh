#!/bin/sh
set -e

# make
cd /src/make-MAKE_VERSION
with gcc -q make/MAKE_VERSION -- env CFLAGS='-O2 -g -D__BEOS__' \
    sh -c './configure --prefix=/usr && ./build.sh && ./make && ./make install'
cd ..

# gawk
cd /src/gawk-GAWK_VERSION
with gcc make -q gawk/GAWK_VERSION -- sh -c './configure --prefix=/usr && make && make install && ln -fs gawk /usr/bin/awk'

# pkgsrc
[ -e /src/pkgsrc ] && mv /src/pkgsrc /var/
if [ -e /var/pkgsrc ]
then
    cd /var/pkgsrc/bootstrap
    with gcc make gawk -q pkgsrc/PKGSRC_VERSION -- env \
        CC='gcc -D_GNU_SOURCE -D_BSD_SOURCE' USE_NATIVE_GCC=yes NOGCCERROR=yes \
        ./bootstrap --prefix=/usr --varbase=/var
    echo gcc gawk > /pkg/pkgsrc/PKGSRC_VERSION/deps
    with -q pkgsrc/PKGSRC_VERSION -- echo -e 'CC=gcc -D_GNU_SOURCE -D_BSD_SOURCE\nUSE_NATIVE_GCC=yes\nNOGCCERROR=yes' \
        >> /etc/mk.conf
fi

# delete the source
cd /
rm -rf /src/
