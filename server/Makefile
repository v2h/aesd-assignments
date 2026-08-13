# Makefile for the AESD Assignment 5 "aesdsocket" application.
#
#   Native build:           make            (or: make all / make default)
#   Cross build (aarch64):  make CROSS_COMPILE=aarch64-none-linux-gnu-
#   Remove build artifacts: make clean
#
# CROSS_COMPILE is empty by default, so the native toolchain is used. When it is
# specified on the command line (with a trailing '-', e.g. aarch64-none-linux-gnu-)
# it prefixes the compiler name, selecting the cross toolchain. Buildroot/Yocto
# pass a fully-qualified CC= on the command line, which overrides CC below.

CROSS_COMPILE ?=
CC      := $(CROSS_COMPILE)gcc
CFLAGS  ?= -Wall -Werror -g
TARGET  := aesdsocket
OBJS    := aesdsocket.o

.PHONY: all default clean

# Both "all" and "default" build the application (assignment requirement).
all: $(TARGET)
default: all

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

aesdsocket.o: aesdsocket.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Remove the aesdsocket application and all object files.
clean:
	rm -f $(TARGET) *.o
