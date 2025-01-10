/*
Copyright (C) 2012-2016 Ben Kurtovic <ben.kurtovic@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#include "textbuffer.h"
#include "memoryarena.h"
#include <stdio.h>

#define INITIAL_CAPACITY 32
#define RESIZE_FACTOR    2

/*
    Create a new textbuffer object.
*/
Textbuffer *
Textbuffer_new(memory_arena_t *a, TokenizerInput *text)
{
    Textbuffer *self = arena_alloc(a, sizeof(Textbuffer));
    self->data = arena_alloc(a, INITIAL_CAPACITY);
    self->length = 0;
    self->capacity = INITIAL_CAPACITY;

    return self;
}

/*
    Deallocate the given textbuffer.
*/
void
Textbuffer_dealloc(memory_arena_t *a, Textbuffer *self)
{
    arena_free(a, self->data);
    arena_free(a, self);
}

/*
    Reset a textbuffer to its initial, empty state.
*/
int
Textbuffer_reset(Textbuffer *self)
{
    self->length = 0;
    return 0;
}

/*
    Write a Unicode codepoint to the given textbuffer.
*/
int
Textbuffer_write(memory_arena_t *a, Textbuffer *self, char c)
{
    if (self->length >= self->capacity) {
        self->data =
            arena_reallocarray(a, self->data, self->capacity * RESIZE_FACTOR, 1);
        if (self->data == NULL)
            return 1;
        self->capacity = self->capacity * RESIZE_FACTOR;
    }

    self->data[self->length] = c;
    self->length++;

    return 0;
}

/*
    Read a Unicode codepoint from the given index of the given textbuffer.

    This function does not check for bounds.
*/
char
Textbuffer_read(Textbuffer *self, size_t index)
{
    return self->data[index];
}

/*
    Concatenate the 'other' textbuffer onto the end of the given textbuffer.
*/
int
Textbuffer_concat(memory_arena_t *a, Textbuffer *self, Textbuffer *other)
{
    size_t newlen = self->length + other->length;

    if (newlen > self->capacity) {
        self->data =
            arena_reallocarray(a, self->data, self->capacity * RESIZE_FACTOR, 1);
        if (self->data == NULL)
            return -1;
        self->capacity = self->capacity * RESIZE_FACTOR;
    }

    memcpy(self->data + self->length, other->data, other->length);
    self->length = newlen;

    return 0;
}

/*
    Null terminated char buffer owned by the caller
*/
char *
Textbuffer_export(memory_arena_t *a, Textbuffer *self)
{
    char *data = arena_alloc(a, self->length + 1);
    memcpy(data, self->data, self->length);
    data[self->length] = 0;
    return data;
}

/*
    Reverse the contents of the given textbuffer.
*/
void
Textbuffer_reverse(Textbuffer *self)
{
    // TODO: IMPLEMENT IF NECCESSARY
    // Py_ssize_t i, end = self->length - 1;
    // Py_UCS4 tmp;

    // for (i = 0; i < self->length / 2; i++) {
    //     tmp = PyUnicode_READ(self->kind, self->data, i);
    //     PyUnicode_WRITE(
    //         self->kind, self->data, i, PyUnicode_READ(self->kind, self->data, end -
    //         i));
    //     PyUnicode_WRITE(self->kind, self->data, end - i, tmp);
    // }
}
