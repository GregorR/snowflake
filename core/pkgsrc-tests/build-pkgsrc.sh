#!/bin/sh
cd /var/pkgsrc
LOG="/root/pkgsrc.log"

SKIP=no
CONTINUE=

try() {
    "$@"
    RET="$?"
    test "$RET" = "0" && echo -n ' |' >> "$LOG" || echo -n 'X|' >> "$LOG"
    return "$RET"
}

[ "$SKIP" != "yes" ] && echo '
D|B|T|pkg
-+-+-+---' > "$LOG"

for pkg in */*/Makefile
do
    pkg=`dirname $pkg`

    if [ "$SKIP" = "yes" ]
    then
        [ "$pkg" != "$CONTINUE" ] && continue
        SKIP=no
        continue
    fi

    # Maybe skip it
    grep "$pkg" /root/broken-*.txt && continue
    expr "$pkg" : '.*/gcc' && continue
    expr "$pkg" : '.*/binutils' && continue
    expr "$pkg" : '.*/gawk' && continue

    cd $pkg
    if try with pkgsrc -- bmake depends
    then
        if try with pkgsrc -- bmake
        then
            if expr "$pkg" : '.*\/p5'
            then
                try false
            else
                try with pkgsrc -- timeout -t 900 bmake test
            fi
            with pkgsrc -- bmake install
        else
            echo -n 'X|' >> "$LOG"
        fi
    else
        echo -n '-|-|' >> "$LOG"
    fi
    echo "$pkg" >> "$LOG"
    cd /var/pkgsrc
done
