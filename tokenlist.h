#pragma once

#include "common.h"

TokenList* TokenList_new(size_t capacity);
void TokenList_deinit(TokenList*);
void TokenList_append(TokenList*, Token*);
/// Expensive. Avoid.
void TokenList_prepend(TokenList*, Token*);

typedef enum {
    Pop_Good = 0,
    Pop_NotFound = 1,
} PopResult;

PopResult Tokenlist_pop(TokenList*, Token*);
PopResult TokenList_pop_first(TokenList*, Token*);