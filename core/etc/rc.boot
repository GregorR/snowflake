#!/bin/sh
export PATH=/usr/bin:/usr/sbin

echo Snowflake booting

mount -t proc proc /proc
mount -t sysfs sys /sys

# only show warning or worse on console
grep -q " verbose" /proc/cmdline && dmesg -n 8 || dmesg -n 3

hwclock -u -s

swapon -a

hostname $(cat /etc/hostname)
ifconfig lo up

# /
mount -o remount,ro /
fsck -A -T -C -p
mount -o remount,rw /

# /dev filesystems
mount -t devtmpfs dev /dev
mkdir -p /dev/shm /dev/pts /tmp/usr
mount -t tmpfs -o nodev,nosuid devshm /dev/shm
mount -t devpts devpts /dev/pts

# and the rest
mount -a
mkdir /tmp/usr

# then our usrview filesystem
pkgresolve -m

[ -f /etc/random-seed ] && cat /etc/random-seed >/dev/urandom
dd if=/dev/urandom of=/etc/random-seed count=1 bs=512 2>/dev/null

dmesg >/var/log/dmesg.log

[ -x /etc/rc.local ] && /etc/rc.local
