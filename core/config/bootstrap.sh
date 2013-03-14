#!/bin/sh
set -e

# pkgsrc
[ -e /src/pkgsrc ] && mv /src/pkgsrc /var/pkgsrc
if [ -e /var/pkgsrc ]
then
    cd /var/pkgsrc/bootstrap

    with snps gcc -q DEFAULT_CONFIGURATION/pkgsrc/PKGSRC_VERSION -- env \
        CC='gcc -D_GNU_SOURCE -D_BSD_SOURCE' USE_NATIVE_GCC=yes NOGCCERROR=yes \
        ./bootstrap --prefix=/usr --varbase=/var

    echo snps gcc gzip > /pkg/DEFAULT_CONFIGURATION/pkgsrc/PKGSRC_VERSION/deps

    # snowflake-ize it
    echo '
# We'\''re on musl, thank you
#LOWER_OPSYS=linux-musl

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

# Some defaults that work better on Snowflake
FAM_DEFAULT=gamin
PAM_DEFAULT=openpam
PKG_OPTIONS.xfce4-exo=-hal
PKG_OPTIONS.xfce4-thunar=-hal
' >> \
        /pkg/DEFAULT_CONFIGURATION/pkgsrc/PKGSRC_VERSION/usr/etc/mk.conf
    echo -e '\tsnps-pkgsrc-install' >> /var/pkgsrc/mk/pkgformat/pkg/package.mk
fi

# delete the source
cd /
rm -rf /src/
