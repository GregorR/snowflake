#!/bin/sh
test "$1" || exit 1
grep 'bmake: stopped in /var/pkgsrc/[^/]*/[^/]*$' "$1" | sort | uniq -c | sort -n
