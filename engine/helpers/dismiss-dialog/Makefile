#
# Cross-compile the dialog helper from macOS for Windows x86_64.
#
#   make         build ./dismiss-dialog.exe
#   make clean   remove build artefacts
#
# Requires Homebrew's mingw-w64 toolchain:
#   brew install mingw-w64

TARGET  ?= dismiss-dialog.exe
CC      ?= x86_64-w64-mingw32-gcc
CFLAGS  ?= -O2 -Wall -Wextra -Wpedantic -municode -DUNICODE -D_UNICODE
LDFLAGS ?= -static -lshell32 -mwindows
SRC      = src/dismiss-dialog.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)
