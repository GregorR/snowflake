#!/bin/sh
exec qemu-system-arm -M vexpress-a9 -kernel vmlinuz \
  -append "console=ttyAMA0 root=b302 rw" -sd snowflake.vmdk -nographic \
  -monitor telnet:localhost:1472,server,nowait,nodelay
