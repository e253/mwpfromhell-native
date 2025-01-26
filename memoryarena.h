#ifndef __MEMORY_ARENA_H
#define __MEMORY_ARENA_H

#include "stddef.h"

typedef struct {
    void** allocations;
    size_t len;
    size_t capacity;
} memory_arena_t;

int arena_init(memory_arena_t*);
void* arena_alloc(memory_arena_t*, size_t);
void* arena_calloc(memory_arena_t*, size_t, size_t);
void* arena_reallocarray(memory_arena_t*, void*, size_t, size_t);
void arena_free(memory_arena_t*, void*);
void arena_clear(memory_arena_t*);

#endif // __MEMORY_ARENA_H