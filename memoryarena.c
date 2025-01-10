#include "memoryarena.h"
#include "assert.h"
#include "stdio.h"
#include "stdlib.h"
#include "string.h"

#define ALLOCATIONS_INITIAL_SIZE  512
#define ALLOCATIONS_RESIZE_FACTOR 2

int
arena_init(memory_arena_t *a)
{
    assert(a);

    a->allocations = malloc(ALLOCATIONS_INITIAL_SIZE * sizeof(void *));
    if (a->allocations == NULL)
        return 1;
    a->len = 0;
    a->capacity = ALLOCATIONS_INITIAL_SIZE;

    return 0;
}

void *
arena_alloc(memory_arena_t *a, size_t sz)
{
    assert(a);
    assert(a->capacity > 0);
    assert(a->len <= a->capacity);

    if (a->len == a->capacity) {
        size_t new_size = a->capacity * ALLOCATIONS_RESIZE_FACTOR;
        a->allocations = reallocarray(a->allocations, new_size, sizeof(void *));
        if (a->allocations == NULL)
            return NULL;
        a->capacity = new_size;
    }

    void *new_alloc = malloc(sz);
    if (new_alloc == NULL)
        return NULL;
    a->allocations[a->len] = new_alloc;
    a->len++;

    return new_alloc;
}

void *
arena_reallocarray(memory_arena_t *a, void *ptr, size_t nmemb, size_t sz)
{
    assert(a);
    if (ptr == NULL)
        return NULL;

    for (int i = 0; i < a->len; i++) {
        if (a->allocations[i] == ptr) {
            void *new_alloc = reallocarray(a->allocations[i], nmemb, sz);
            if (new_alloc == NULL)
                return NULL;

            a->allocations[i] = new_alloc;

            return new_alloc;
        }
    }

    return NULL;
}

void
arena_free(memory_arena_t *a, void *ptr)
{
    assert(a);

    if (a->len == 0)
        return;

    for (int i = 0; i < a->len; i++) {
        if (a->allocations[i] == ptr) {
            free(ptr);
            a->allocations[i] = NULL;
            return;
        }
    }
}

void
arena_clear(memory_arena_t *a)
{
    assert(a);

    for (int i = 0; i < a->len; i++) {
        if (a->allocations[i] != NULL)
            free(a->allocations[i]);
    }

    free(a->allocations);

    a->allocations = NULL;
    a->capacity = 0;
    a->len = 0;
}