#!/bin/bash -x
# Build a root filesystem
# 
# Copyright (C) 2012 Gregor Richards
# 
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

if [ ! "$SNOWFLAKE_BASE" ]
then
    SNOWFLAKE_BASE="$PWD"
fi

. "$SNOWFLAKE_BASE"/defs.sh

inchroot() {
    $SUDO chroot "$SNOWFLAKE_PREFIX" "$@"
}

# check that we have all the filesystems we need
FILESYSTEMS="proc sysfs devtmpfs tmpfs aufs"
for fs in $FILESYSTEMS
do
    $SUDO modprobe $fs 2> /dev/null
    if [ ! "`grep '\s'$fs'$' /proc/filesystems`" ]
    then
        echo 'To chroot into Snowflake, your host kernel must support the following filesystems: '"$FILESYSTEMS"
        exit 1
    fi
done

inchroot sh -c 'mount -t proc proc /proc;
                mount -t sysfs sys /sys;
                mount -t devtmpfs dev /dev;
                mount -t tmpfs tmp /tmp;
                mkdir /tmp/usr'
if [ "$1" ]
then
    inchroot pkgresolve -- "$@"
else
    inchroot pkgresolve -- su -
fi

$SUDO umount "$SNOWFLAKE_PREFIX"/{proc,sys,dev,tmp}
