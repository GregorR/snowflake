#!/bin/sh
ionice -c 3 nice -n 10 ./build-pkgsrc.sh >& log.txt < /dev/null
