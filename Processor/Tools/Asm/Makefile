CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11

all: m65f32asm m65f32dis

m65f32asm: m65f32asm.c
	$(CC) $(CFLAGS) -o $@ $<

m65f32dis: m65f32dis.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f m65f32asm m65f32dis

.PHONY: all clean
