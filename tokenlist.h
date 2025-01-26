#pragma once

#include "common.h"
#include "memoryarena.h"

TokenList* TokenList_new(memory_arena_t*, size_t capacity);
void TokenList_deinit(TokenList*);
void TokenList_append(memory_arena_t*, TokenList*, Token*);
/// Expensive. Avoid.
void TokenList_prepend(memory_arena_t*, TokenList*, Token*);

typedef enum {
    Pop_Good = 0,
    Pop_NotFound = 1,
} PopResult;

PopResult Tokenlist_pop(TokenList*, Token*);
PopResult TokenList_pop_first(TokenList*, Token*);