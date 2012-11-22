#!/bin/sh
exec qemu-system-x86_64 -hda snowflake.img -curses \
  -monitor telnet:localhost:2642,server,nowait,nodelay
