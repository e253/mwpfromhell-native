/*
Copyright (C) 2012-2017 Ben Kurtovic <ben.kurtovic@gmail.com>

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

#pragma once

#include "Python.h"
#include "avl_tree.h"
#include "definitions.h"
#include "tokens.h"
#include <assert.h>
#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BOMB_PY_METHOD(name)                               \
    printf("Hit method not implemented yet: %s\n", #name); \
    exit(1);

/* Error handling macros */

#define BAD_ROUTE self->route_state
#define BAD_ROUTE_CONTEXT self->route_context
#define FAIL_ROUTE(context)            \
    do {                               \
        self->route_state = 1;         \
        self->route_context = context; \
    } while (0)
#define RESET_ROUTE() self->route_state = 0

/* Shared globals */

extern char** entitydefs;

extern PyObject* NOARGS;
extern PyObject* definitions;

/* Structs */

typedef struct {
    char* data;
    size_t length;
    size_t capacity;
} Textbuffer;

typedef struct {
    size_t head;
    uint64_t context;
} StackIdent;

typedef struct
{
    Token* tokens;
    size_t len;
    size_t capacity;
} TokenList;

struct Stack {
    TokenList* tokenlist;
    uint64_t context;
    Textbuffer* textbuffer;
    StackIdent ident;
    struct Stack* next;
};
typedef struct Stack Stack;

typedef struct {
    size_t length;
    const char* data;
} TokenizerInput;

typedef struct avl_tree_node avl_tree;

typedef struct {
    StackIdent id;
    struct avl_tree_node node;
} route_tree_node;

typedef struct {
    TokenizerInput text; /* text to tokenize */
    Stack* topstack; /* topmost stack */
    size_t head; /* current position in text */
    int global; /* global context */
    int depth; /* stack recursion depth */
    int route_state; /* whether a BadRoute has been triggered */
    uint64_t route_context; /* context when the last BadRoute was triggered */
    avl_tree* bad_routes; /* stack idents for routes known to fail */
    int skip_style_tags; /* temp fix for the sometimes broken tag parser */
} Tokenizer;
