CC=gcc
CFLAGS=-O2 -g
LD=$(CC)
LDFLAGS=

OBJS=usrview.o

all: usrview

usrview: $(OBJS)
	$(LD) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

suid: usrview
	chown root:root usrview
	chmod 4755 usrview

clean:
	rm -f usrview *.o
