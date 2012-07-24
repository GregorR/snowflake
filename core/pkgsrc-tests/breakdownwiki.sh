#!/bin/sh
if [ ! "$3" ]
then
    echo 'Use: breakdownwiki.sh <snowflake rev> <pkgsrc patches> <musl version>' >&2
    exit 1
fi
SF_REV="$1"
PATCHES="$2"
MUSL_V="$3"

printf '%s\n' 'This is an automatically-generated report of NetBSD pkgsrc build results from [[https://bitbucket.org/GregorR/snowflake|Snowflake]] revision '"$SF_REV"', using musl '"$MUSL_V"'. The purpose of this report is to give a general idea of what packages do and do not build on musl. When possible, you should refer to manually created build instructions rather than this automatically generated table.

Each row indicates whether the dependencies for a package built, whether the package itself built, whether the package passed its tests, and any patches against pkgsrc which were necessary to build the package. Please note that the pkgsrc tests build '\'\''every'\'\'' package with the CFLAGS -D_GNU_SOURCE -D_BSD_SOURCE, so information on whether they are needed will be lost.

If you have patches to make other packages build, please report them on the [[https://bitbucket.org/GregorR/snowflake/issues|Snowflake issue tracker]].

----
'

printf '%s\n' "||'''Deps'''||'''Builds'''||'''Tests'''||'''Package/patches'''||"
tail -n+4 | while read ln
do
    [ "$ln" = "" ] && continue

    pkgdiff=`printf '%s' "$ln" | cut -d'|' -f4 | sed 's/\//-/ ; s/$/.diff/'`

    # Maybe switch it for a link
    if [ -e "$PATCHES/$pkgdiff" ]
    then
        printf '%s\n' "$ln" | sed 's#^\([^|]*|.|.|\)\(.*\)#\1[[https://bitbucket.org/GregorR/snowflake/src/'$SF_REV'/pkgsrc-patches/'$pkgdiff'__LINK__\2]]#'
    else
        printf '%s\n' "$ln"
    fi
done | \
    sed 's/^|/ |/ ; s/|/||/g ; s/__LINK__/|/ ; s/^/||/ ; s/$/||/ ; s/|\([X-]\)|/|<:#FF0000>\1|/g ; s/| |/|<#00FF00> |/g'
