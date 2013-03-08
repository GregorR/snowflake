#!/bin/sh
[ "$2" ] || exit 1

TA=/tmp/$$.a
TB=/tmp/$$.b

grep -v '^X' "$1" > $TA
grep -v '^X' "$2" > $TB

diff $TA $TB | grep '^> ..X' | while read BLN
do
    PKG=`echo "$BLN" | cut -d'|' -f4`
    ALN=`grep '^ .*'"$PKG"'$' $TA`
    if [ "$ALN" ]
    then
        echo "< $ALN"
        echo "$BLN"
    fi
done

rm -f $TA $TB
