# Makefile for the AESD Assignment 2 "writer" application.
#
#   Native build:           make
#   Cross build (aarch64):  make CROSS_COMPILE=aarch64-none-linux-gnu-
#   Remove build artifacts: make clean
#
# CROSS_COMPILE is empty by default, so the native toolchain is used. When it is
# specified on the command line (with a trailing '-', e.g. aarch64-none-linux-gnu-)
# it prefixes the compiler name, selecting the cross toolchain.

CROSS_COMPILE ?=
CC      := $(CROSS_COMPILE)gcc
CFLAGS  ?= -Wall -Werror -g
TARGET  := writer
OBJS    := writer.o

.PHONY: all clean

# Default target: build the writer application.
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

writer.o: writer.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Remove the writer application and all object files.
clean:
	rm -f $(TARGET) *.o
