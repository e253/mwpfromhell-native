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

#include "common.h"
#include "tokenlist.h"
#include "tok_support.h"
#include "textbuffer.h"

/*
    Add a new token stack, context, and textbuffer to the list.
*/
int
Tokenizer_push(Tokenizer *self, uint64_t context)
{
    Stack *top = malloc(sizeof(Stack));
    assert(top);

    top->tokenlist = TokenList_new(0);
    top->context = context;
    top->textbuffer = Textbuffer_new(&self->text);
    assert(top->textbuffer);

    top->ident.head = self->head;
    top->ident.context = context;
    top->next = self->topstack;
    self->topstack = top;
    self->depth++;
    return 0;
}

/*
    Push the textbuffer onto the stack as a Text node and clear it.
*/
int
Tokenizer_push_textbuffer(Tokenizer *self)
{
    PyObject *text, *kwargs, *token;
    Textbuffer *buffer = self->topstack->textbuffer;

    if (buffer->length == 0) {
        return 0;
    }

    Token t;
    t.type = Text;
    t.ctx.data = Textbuffer_export(buffer);
    TokenList_append(self->topstack->tokenlist, &t);

    Textbuffer_reset(buffer);

    return 0;
}

/*
    Pop and deallocate the top token stack/context/textbuffer.
*/
void
Tokenizer_delete_top_of_stack(Tokenizer *self)
{
    Stack *top = self->topstack;

    // TODO: Make sure everything is de-allocated here.

    Textbuffer_dealloc(top->textbuffer);
    self->topstack = top->next;
    free(top);
    self->depth--;
}

/*
    Pop the current stack/context/textbuffer, returing the stack.
*/
TokenList *
Tokenizer_pop(Tokenizer *self)
{
    if (Tokenizer_push_textbuffer(self))
        return NULL;
    TokenList* tl = self->topstack->tokenlist;
    Tokenizer_delete_top_of_stack(self);
    return tl;
}

/*
    Pop the current stack/context/textbuffer, returing the stack. We will also
    replace the underlying stack's context with the current stack's.
*/
TokenList *
Tokenizer_pop_keeping_context(Tokenizer *self)
{
    uint64_t context;

    if (Tokenizer_push_textbuffer(self)) {
        return NULL;
    }
    TokenList* tl = self->topstack->tokenlist;
    context = self->topstack->context;
    Tokenizer_delete_top_of_stack(self);
    self->topstack->context = context;
    return tl;
}

/*
    Compare two route_tree_nodes that are in their avl_tree_node forms.
*/
static int
compare_nodes(const struct avl_tree_node *na, const struct avl_tree_node *nb)
{
    route_tree_node *a = avl_tree_entry(na, route_tree_node, node);
    route_tree_node *b = avl_tree_entry(nb, route_tree_node, node);

    if (a->id.head < b->id.head) {
        return -1;
    }
    if (a->id.head > b->id.head) {
        return 1;
    }
    return (a->id.context > b->id.context) - (a->id.context < b->id.context);
}

/*
    Remember that the current route (head + context at push) is invalid.

    This will be noticed when calling Tokenizer_check_route with the same head
    and context, and the route will be failed immediately.
*/
void
Tokenizer_memoize_bad_route(Tokenizer *self)
{
    route_tree_node *node = malloc(sizeof(route_tree_node));
    if (node) {
        node->id = self->topstack->ident;
        if (avl_tree_insert(&self->bad_routes, &node->node, compare_nodes)) {
            free(node);
        }
    }
}

/*
    Fail the current tokenization route. Discards the current
    stack/context/textbuffer and sets the BAD_ROUTE flag. Also records the
    ident of the failed stack so future parsing attempts down this route can be
    stopped early.
*/
void *
Tokenizer_fail_route(Tokenizer *self)
{
    uint64_t context = self->topstack->context;
    PyObject *stack;

    Tokenizer_memoize_bad_route(self);
    stack = Tokenizer_pop(self);
    Py_XDECREF(stack);
    FAIL_ROUTE(context);
    return NULL;
}

/*
    Check if pushing a new route here with the given context would definitely
    fail, based on a previous call to Tokenizer_fail_route() with the same
    stack. (Or any other call to Tokenizer_memoize_bad_route().)

    Return 0 if safe and -1 if unsafe. The BAD_ROUTE flag will be set in the
    latter case.

    This function is not necessary to call and works as an optimization
    implementation detail. (The Python tokenizer checks every route on push,
    but this would introduce too much overhead in C tokenizer due to the need
    to check for a bad route after every call to Tokenizer_push.)
*/
int
Tokenizer_check_route(Tokenizer *self, uint64_t context)
{
    StackIdent ident = {self->head, context};
    struct avl_tree_node *node = (struct avl_tree_node *) (&ident + 1);

    if (avl_tree_lookup_node(self->bad_routes, node, compare_nodes)) {
        FAIL_ROUTE(context);
        return -1;
    }
    return 0;
}

/*
    Free the tokenizer's bad route cache tree. Intended to be called by the
    main tokenizer function after parsing is finished.
*/
void
Tokenizer_free_bad_route_tree(Tokenizer *self)
{
    struct avl_tree_node *cur = avl_tree_first_in_postorder(self->bad_routes);
    struct avl_tree_node *parent;
    while (cur) {
        route_tree_node *node = avl_tree_entry(cur, route_tree_node, node);
        parent = avl_get_parent(cur);
        free(node);
        cur = avl_tree_next_in_postorder(cur, parent);
    }
    self->bad_routes = NULL;
}

/*
    Write a token to the current token stack.
*/
int
Tokenizer_emit_token(Tokenizer *self, Token *token, int first)
{
    if (Tokenizer_push_textbuffer(self)) {
        return 1;
    }

    if (first) {
        TokenList_prepend(self->topstack->tokenlist, token);
    } else {
        TokenList_append(self->topstack->tokenlist, token);
    }

    return 0;    
}

/*
    Write a token to the current token stack, with kwargs. Steals a reference
    to kwargs.
*/
int
Tokenizer_emit_token_kwargs(Tokenizer *self,
                            Token *token,
                            PyObject *kwargs,
                            int first)
{
    BOMB_PY_METHOD(Tokenizer_emit_token_kwargs)
    //PyObject *instance;

    //if (Tokenizer_push_textbuffer(self)) {
    //    Py_DECREF(kwargs);
    //    return -1;
    //}
    //instance = PyObject_Call(token, NOARGS, kwargs);
    //if (!instance) {
    //    Py_DECREF(kwargs);
    //    return -1;
    //}
    //if (first ? PyList_Insert(self->topstack->stack, 0, instance)
    //          : PyList_Append(self->topstack->stack, instance)) {
    //    Py_DECREF(instance);
    //    Py_DECREF(kwargs);
    //    return -1;
    //}
    //Py_DECREF(instance);
    //Py_DECREF(kwargs);
    //return 0;
}

/*
    Write a Unicode codepoint to the current textbuffer.
*/
int
Tokenizer_emit_char(Tokenizer *self, Py_UCS4 code)
{
    return Textbuffer_write(self->topstack->textbuffer, code);
}

/*
    Write a string of text to the current textbuffer.
*/
int
Tokenizer_emit_text(Tokenizer *self, const char *text)
{
    int i = 0;

    while (text[i]) {
        if (Tokenizer_emit_char(self, text[i])) {
            return -1;
        }
        i++;
    }
    return 0;
}

/*
    Write the contents of another textbuffer to the current textbuffer,
    deallocating it in the process.
*/
int
Tokenizer_emit_textbuffer(Tokenizer *self, Textbuffer *buffer)
{
    int retval = Textbuffer_concat(self->topstack->textbuffer, buffer);
    Textbuffer_dealloc(buffer);
    return retval;
}

/*
    Write a series of tokens to the current stack at once.
*/
int
Tokenizer_emit_all(Tokenizer *self, TokenList *tokenlist)
{
    Tokenizer_push_textbuffer(self);

    for (int i = 0; i < tokenlist->len; i++)
        TokenList_append(self->topstack->tokenlist, &tokenlist->tokens[i]);
    
    return 0;
}

/*
    Pop the current stack, write text, and then write the stack. 'text' is a
    NULL-terminated array of chars.
*/
int
Tokenizer_emit_text_then_stack(Tokenizer *self, const char *text)
{
    TokenList *tl = Tokenizer_pop(self);

    if (Tokenizer_emit_text(self, text))
        return -1;

    if (tl && tl->len > 0) {
        if (Tokenizer_emit_all(self, tl))
            return -1;
    }

    self->head--;
    return 0;
}

/*
    Read the value at a relative point in the wikicode, forwards.
*/
char
Tokenizer_read(Tokenizer *self, size_t delta)
{
    size_t index = self->head + delta;

    if (index >= self->text.length) {
        return '\0';
    }

    return self->text.data[index];
}

/*
    Read the value at a relative point in the wikicode, backwards.
*/
char
Tokenizer_read_backwards(Tokenizer *self, size_t delta)
{
    size_t index;

    if (delta > self->head) {
        return '\0';
    }

    return self->text.data[self->head - delta];
}
