#include "tokenlist.h"
#include "common.h"

#define INITIAL_CAPACITY 32
#define RESIZE_FACTOR 2

TokenList* TokenList_new(size_t capacity) {
    TokenList* tl = malloc(sizeof(TokenList));
    tl->tokens = malloc(INITIAL_CAPACITY * sizeof(Token));
    tl->len = 0;
    if (capacity != 0) {
        tl-> capacity = capacity;
    } else {
        tl->capacity = INITIAL_CAPACITY;
    }

    return tl;
}

static inline void TokenList_resize(TokenList* tl) {
    tl->capacity = tl->capacity * RESIZE_FACTOR;
    tl->tokens = reallocarray(tl->tokens, tl->capacity, sizeof(Token));
}

void TokenList_append(TokenList* tl, Token* t) {
    if (tl->len == tl->capacity)
        TokenList_resize(tl);

    tl->tokens[tl->len] = *t;
    tl->len++;
}

void TokenList_prepend(TokenList* tl, Token* t) {
    if (tl->len == 0)
        return TokenList_append(tl, t);

    if (tl->len == tl->capacity)
        TokenList_resize(tl);

    for (int i = tl->len; i > 0; i--)
        tl->tokens[i] = tl->tokens[i - 1];
    
    tl->tokens[0] = *t;

    tl->len++;

    return;
}
