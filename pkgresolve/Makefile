CC=gcc
CFLAGS=-O2 -g
LD=$(CC)
LDFLAGS=

OBJS=pkgresolve.o

all: pkgresolve

pkgresolve: $(OBJS)
	$(LD) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f pkgresolve *.o
