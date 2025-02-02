SOURCES := $(wildcard *.c)
INCLUDES := $(wildcard *.h)

libmwfromhell.o: $(SOURCES) $(INCLUDES)
	zig cc -c libmwfromhell.c -o libmwfromhell.o

test: libmwfromhell.o
	zig test test.zig libmwfromhell.o -lc -I.

clean:
	rm -f test libmwfromhell.o

