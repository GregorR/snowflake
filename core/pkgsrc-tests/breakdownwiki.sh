#!/bin/sh
if [ ! "$4" ]
then
    echo 'Use: breakdownwiki.sh <snowflake rev> <pkgsrc-patches rev> <pkgsrc patches> <musl version>' >&2
    exit 1
fi
SF_REV="$1"
PP_REV="$2"
PATCHES="$3"
MUSL_V="$4"

printf '%s\n' 'This is an automatically-generated report of NetBSD pkgsrc build results from [[http://bitbucket.org/GregorR/snowflake|Snowflake]] revision '"$SF_REV"', using musl '"$MUSL_V"'. The purpose of this report is to give a general idea of what packages do and do not build on musl. When possible, you should refer to manually created build instructions rather than this automatically generated table.

Each row indicates whether the dependencies for a package built, whether the package itself built, whether the package passed its tests, and any patches against pkgsrc which were necessary to build the package.

If you have patches to make other packages build, please report them on the [[https://bitbucket.org/GregorR/musl-pkgsrc-patches/issues|musl-pkgsrc-patches issue tracker]].

----
'

SCMD='s/^|/ |/ ; s/^/|/ ; s/| /__BAR____BAR__bgcolor="green"__BAR__ /g ; s/|\([X-]\)/__BAR____BAR__bgcolor="red"__BAR__\1/g ; s/__BAR__/|/g ; s/__LINK__/ /g'

printf '%s\n%s\n%s\n%s\n' '{| class="wikitable sortable"' '|-' '! Deps !! Builds !! Tests !! Package/patches' '|-'
tail -n+4 | while read ln
do
    [ "$ln" = "" ] && continue

    pkgdiff=`printf '%s' "$ln" | cut -d'|' -f4 | sed 's/\//-/ ; s/$/.diff/'`

    # Maybe switch it for a link
    if [ -e "$PATCHES/$pkgdiff" ]
    then
        printf '%s\n' "$ln" | sed 's#^\([^|]*|.|.|\)\(.*\)#\1[[https://bitbucket.org/GregorR/musl-pkgsrc-patches/src/'$PP_REV'/'$pkgdiff'__LINK__\2]]# ; '"$SCMD"
    else
        printf '%s\n' "$ln" | sed "$SCMD"
    fi
    printf '%s\n' '|-'
done
