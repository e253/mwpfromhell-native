/*
Copyright (C) 2012-2018 Ben Kurtovic <ben.kurtovic@gmail.com>

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

#include "common.h"
#include "memoryarena.h"

/* Functions */

int Tokenizer_push(memory_arena_t*, Tokenizer*, uint64_t);
int Tokenizer_push_textbuffer(memory_arena_t*, Tokenizer*);
void Tokenizer_delete_top_of_stack(memory_arena_t*, Tokenizer*);
TokenList* Tokenizer_pop(memory_arena_t*, Tokenizer*);
TokenList* Tokenizer_pop_keeping_context(memory_arena_t*, Tokenizer*);
void Tokenizer_memoize_bad_route(memory_arena_t*, Tokenizer*);
void* Tokenizer_fail_route(memory_arena_t* a, Tokenizer*);
int Tokenizer_check_route(Tokenizer*, uint64_t);
void Tokenizer_free_bad_route_tree(Tokenizer*);

int Tokenizer_emit_token(memory_arena_t*, Tokenizer*, Token*, int);
int Tokenizer_emit_char(memory_arena_t*, Tokenizer*, char);
int Tokenizer_emit_text(memory_arena_t*, Tokenizer*, const char*);
int Tokenizer_emit_textbuffer(memory_arena_t*, Tokenizer*, Textbuffer*);
int Tokenizer_emit_all(memory_arena_t*, Tokenizer*, TokenList*);
int Tokenizer_emit_text_then_stack(memory_arena_t*, Tokenizer*, const char*);

char Tokenizer_read(Tokenizer*, size_t);
char Tokenizer_read_backwards(Tokenizer*, size_t);

/* Macros */

#define MAX_DEPTH 100
#define Tokenizer_CAN_RECURSE(self) (self->depth < MAX_DEPTH)
#define Tokenizer_IS_CURRENT_STACK(self, id) \
    (self->topstack->ident.head == (id).head && self->topstack->ident.context == (id).context)

#define Tokenizer_emit(a, self, token) Tokenizer_emit_token(a, self, token, 0)
#define Tokenizer_emit_first(a, self, token) Tokenizer_emit_token(a, self, token, 1)
// #define Tokenizer_emit_kwargs(self, token, kwargs) \
//     Tokenizer_emit_token_kwargs(self, token, kwargs, 0)
// #define Tokenizer_emit_first_kwargs(self, token, kwargs) \
//     Tokenizer_emit_token_kwargs(self, token, kwargs, 1)
