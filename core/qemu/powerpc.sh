#!/bin/sh
exec qemu-system-ppc -snapshot -M g3beige -kernel vmlinux \
    -append "console=ttyS0 root=0302 rw" -hda snowflake.vmdk -nographic \
    -monitor telnet:localhost:2003,server,nowait,nodelay
