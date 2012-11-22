#!/bin/sh
exec qemu-system-mips -M malta -kernel vmlinux \
  -append "console=ttyS0 root=0302 rw" -hda snowflake.img -nographic \
  -monitor telnet:localhost:7802,server,nowait,nodelay
