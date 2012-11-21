CC=gcc
CFLAGS=-O2 -g
LD=$(CC)
LDFLAGS=

DEFAULT_CONFIGURATION=x86_64-linux-musl

OBJS=pkgresolve.o

all: pkgresolve

pkgresolve: $(OBJS)
	$(LD) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -DDEFAULT_CONFIGURATION=\"$(DEFAULT_CONFIGURATION)\" -c $< -o $@

clean:
	rm -f pkgresolve *.o
