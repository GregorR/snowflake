#!/bin/sh
L=/tmp/pkgsrc.log
tail -n+4 pkgsrc.log > $L

ATTEMPTED=`wc -l < $L`
DEPS_FAILED=`grep '^X|' $L | wc -l`
BUILD_TRIED=`grep '^ |' $L | wc -l`
BUILD_FAILED=`grep '^ |X|' $L | wc -l`
TESTS_FAILED=`grep '^ | |X|' $L | wc -l`
SUCCESS=`grep '^ | | |' $L | wc -l`
PERCENT=`echo "$SUCCESS $BUILD_TRIED / 100 "'* p' | dc`'%'

echo -e \
'Attempted:\t'"$ATTEMPTED"'
Deps failed:\t'"$DEPS_FAILED"'
Build tried:\t'"$BUILD_TRIED"'
Build failed:\t'"$BUILD_FAILED"'
Tests failed:\t'"$TESTS_FAILED"'
Success:\t'"$SUCCESS"' ('"$PERCENT"')

Summary: Tried '"$ATTEMPTED"', depfail '"$DEPS_FAILED"', depok '"$BUILD_TRIED"', nobuild '"$BUILD_FAILED"', testfail '"$TESTS_FAILED"', success '"$SUCCESS"' ('"$PERCENT"')'

rm -f $L
