#!/bin/sh

usage() {
	echo "Usage: $0 <img file> <directory or tarball of content> <img size> [options]"
	echo "options: --clear-builds --copy-tarballs --zero-fill"
	echo
	echo "--clear-builds will remove stuff in /src/build (butch 0.0.8+ build directory)"
	echo '--copy-tarballs will copy tarballs from directory pointed to by "C" env var'
	echo "--zero-fill will fill the rest of the hd image with zero for better compressability"
	echo
	echo "<img size> will be passed directly to dd, so you can use whatever value dd supports, i.e. 8G"
	exit 1
}

die() {
	echo "$1"
	[ -d "$mountdir" ] && rmdir "$mountdir"
	exit 1
}

die_unloop() {
	sync
	losetup -d "$loopdev"
	die "$1"
}

die_unmount() {
	umount "$mountdir" || die_unloop 'Failed to unmount /boot'
	die_unloop "$1"
}

run_echo() {
	printf "%s\n", "$@"
	"$@"
}

mountdir=

which extlinux 2>&1 > /dev/null || die 'extlinux must be in PATH (try installing syslinux)'
if [ -z "$UID" ] ; then
	UID="`id -u`"
fi
[ "$UID" = "0" ] || die "must be root"

imagefile="$1"
[ -z "$imagefile" ] && usage

contents="$2"
[ -z "$contents" ] && usage
[ ! -f "$contents" ] && [ ! -d "$contents" ] && die "failed to access $contents"

imagesize="$3"
[ -z "$imagesize" ] && usage

for mbr_bin in mbr.bin /usr/lib/syslinux/mbr.bin /usr/share/syslinux/mbr.bin 
	do [ -f "$mbr_bin" ] && break ; done

[ -z "$mbr_bin" ] && die 'Could not find mbr.bin'

echo "1) make the image file"
dd if=/dev/zero of="$imagefile" bs=1 count=0 seek="$imagesize" || die "Failed to create $imagefile"

echo "2) fdisk"
echo 'n
p
1
2048
+100M
n
p
2


a
1
w' | fdisk "$imagefile" || die "fdisk failed"

part1_start=`echo "512 * 2048" | bc`
part1_size=`echo "100 * 1024 * 1024" | bc`
part2_start=`echo "$part1_start + $part1_size" | bc`

echo '3) copy mbr'
dd conv=notrunc if="$mbr_bin" of="$imagefile" || die 'Failed to set up MBR'

echo '4) /boot'
loopdev=`losetup -f`
mountdir="/tmp/mnt.$$"

echo "info: mounting $imagefile as $loopdev on $mountdir"

run_echo losetup -o $part1_start --sizelimit $part1_size "$loopdev" "$imagefile" || die 'Failed to losetup for /boot'
mkdir -p "$mountdir" || die_unloop 'Failed to create '"$mountdir"
mkfs.ext3 "$loopdev" || die_unloop 'Failed to mkfs.ext3 loop for /boot'
mount "$loopdev" "$mountdir" || die_unloop 'Failed to mount loop for /boot'

if [ -d "$contents" ] ; then
	cp -a "$contents"/boot/* "$mountdir"/ || die_unmount 'Failed to copy boot'
else
	tar -C "$mountdir" -xf "$contents" boot || die_unmount 'Failed to extract boot'
	mv "$mountdir"/boot/* "$mountdir"/ || die_unmount 'Failed to move /boot content to root of boot partition'
	rmdir "$mountdir"/boot
fi
sed -i 's/sda1/sda2/g' "$mountdir"/extlinux.conf || die_unmount 'Failed to reconfigure extlinux.conf'
extlinux -i "$mountdir"/ || die_unmount 'Failed to install extlinux'
umount "$mountdir" || die_unloop 'Failed to unmount /boot'
sync
losetup -d "$loopdev"

echo ' 5) /'
loopdev=`losetup -f`
run_echo losetup -o $part2_start "$loopdev" "$imagefile" || die 'Failed to losetup for /'
mkfs.ext3 "$loopdev" || die_unloop 'Failed to mkfs.ext3 loop for /'
mount "$loopdev" "$mountdir" || die_unloop 'Failed to mount loop for /'

echo "copying contents, this will take a while"
if [ -d "$contents" ]
then
	cp -a "$contents"/* "$mountdir"/ || die_unmount 'Failed to copy /'
else
	tar -C "$mountdir" -zxf "$contents" || die_unmount 'Failed to extract /'
fi
rm -f "$mountdir"/boot/*
echo '/dev/sda1 /boot ext3 defaults 0 0' >> "$mountdir"/pkg/core/1.0/etc/fstab || die_unmount 'Failed to extend fstab'
umount "$mountdir" || die_unloop 'Failed to unmount /'
sync
losetup -d "$loopdev"

# cleanup
rmdir "$mountdir" || die "Failed to remove $mountdir"

echo 'Done.'

