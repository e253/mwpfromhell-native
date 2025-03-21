/*
Copyright (C) 2012-2021 Ben Kurtovic <ben.kurtovic@gmail.com>

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

#include "tok_parse.h"
#include "common.h"
#include "contexts.h"
#include "memoryarena.h"
#include "tag_data.h"
#include "textbuffer.h"
#include "tok_support.h"
#include "tokens.h"

#define DIGITS          "0123456789"
#define HEXDIGITS       "0123456789abcdefABCDEF"
#define ALPHANUM        "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
#define URISCHEME       "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+.-"

#define MAX_BRACES      255
#define MAX_ENTITY_SIZE 8

typedef struct {
    TokenList *title;
    int level;
} HeadingData;

/* Forward declarations */

static TokenList *
Tokenizer_really_parse_external_link(memory_arena_t *, Tokenizer *, int, Textbuffer *);
static int Tokenizer_parse_entity(memory_arena_t *, Tokenizer *);
static int Tokenizer_parse_comment(memory_arena_t *, Tokenizer *);
static int Tokenizer_handle_dl_term(memory_arena_t *, Tokenizer *);
static int Tokenizer_parse_tag(memory_arena_t *, Tokenizer *);

/*
    Determine whether the given code point is a marker.
*/
static int
is_marker(char this)
{
    int i;

    for (i = 0; i < NUM_MARKERS; i++) {
        if (MARKERS[i] == this) {
            return 1;
        }
    }
    return 0;
}

/*
    Given a context, return the heading level encoded within it.
*/
static int
heading_level_from_context(uint64_t n)
{
    int level;

    n /= LC_HEADING_LEVEL_1;
    for (level = 1; n > 1; n >>= 1) {
        level++;
    }
    return level;
}

/*
    Sanitize the name of a tag so it can be compared with others for equality.
    The token argument must have `type=Text`
*/
static int
strip_tag_name(Token *token, int take_attr)
{
    // PyObject *text, *rstripped, *lowered;

    assert(token->type == Text);

    // rstrip text
    size_t len = strlen(token->ctx.data);
    char *text = token->ctx.data;
    int text_end = len - 1;

    while (text_end > 0 && isspace(text[text_end]))
        text_end--;

    text[text_end + 1] = 0;

    for (int i = 0; i <= text_end; i++) {
        if (isupper(text[i]))
            text[i] += 32;
    }

    return 0;
}

/*
    Parse a template at the head of the wikicode string.
*/
static int
Tokenizer_parse_template(memory_arena_t *a, Tokenizer *self, int has_content)
{
    size_t reset = self->head;
    uint64_t context = LC_TEMPLATE_NAME;

    if (has_content) {
        context |= LC_HAS_TEMPLATE;
    }

    TokenList *template = Tokenizer_parse(a, self, context, 1);
    if (BAD_ROUTE) {
        self->head = reset;
        return 0;
    }
    if (!template) {
        return 1;
    }

    Token open;
    open.type = TemplateOpen;
    open.ctx.data = NULL;
    if (Tokenizer_emit_first(a, self, &open)) {
        return 1;
    }
    if (Tokenizer_emit_all(a, self, template)) {
        return 1;
    }
    Token close;
    close.type = TemplateClose;
    close.ctx.data = NULL;
    if (Tokenizer_emit(a, self, &close)) {
        return 1;
    }
    return 0;
}

/*
    Parse an argument at the head of the wikicode string.
*/
static int
Tokenizer_parse_argument(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;

    TokenList *argument = Tokenizer_parse(a, self, LC_ARGUMENT_NAME, 1);
    if (BAD_ROUTE) {
        self->head = reset;
        return 0;
    }
    if (!argument) {
        return 1;
    }

    TOKEN(open, ArgumentOpen)
    if (Tokenizer_emit_first(a, self, &open)) {
        return 1;
    }
    if (Tokenizer_emit_all(a, self, argument)) {
        return 1;
    }
    TOKEN(close, ArgumentClose)
    if (Tokenizer_emit(a, self, &close)) {
        return 1;
    }
    return 0;
}

/*
    Parse a template or argument at the head of the wikicode string.
*/
static int
Tokenizer_parse_template_or_argument(memory_arena_t *a, Tokenizer *self)
{
    unsigned int braces = 2, i;
    int has_content = 0;
    TokenList *tokenlist = self->topstack->tokenlist;

    self->head += 2;
    while (Tokenizer_read(self, 0) == '{' && braces < MAX_BRACES) {
        self->head++;
        braces++;
    }
    if (Tokenizer_push(a, self, 0)) {
        return 1;
    }
    while (braces) {
        if (braces == 1) {
            if (Tokenizer_emit_text_then_stack(a, self, "{")) {
                return 1;
            }
            return 0;
        }
        if (braces == 2) {
            if (Tokenizer_parse_template(a, self, has_content)) {
                return 1;
            }
            if (BAD_ROUTE) {
                RESET_ROUTE();
                if (Tokenizer_emit_text_then_stack(a, self, "{{")) {
                    return 1;
                }
                return 0;
            }
            break;
        }
        if (Tokenizer_parse_argument(a, self)) {
            return 1;
        }
        if (BAD_ROUTE) {
            RESET_ROUTE();
            if (Tokenizer_parse_template(a, self, has_content)) {
                return 1;
            }
            if (BAD_ROUTE) {
                char text[MAX_BRACES + 1];
                RESET_ROUTE();
                for (i = 0; i < braces; i++) {
                    text[i] = '{';
                }
                text[braces] = '\0';
                if (Tokenizer_emit_text_then_stack(a, self, text)) {
                    return -1;
                }
                return 0;
            } else {
                braces -= 2;
            }
        } else {
            braces -= 3;
        }
        if (braces) {
            has_content = 1;
            self->head++;
        }
    }
    tokenlist = Tokenizer_pop(a, self);
    if (!tokenlist)
        return 1;
    if (Tokenizer_emit_all(a, self, tokenlist))
        return 1;
    if (self->topstack->context & LC_FAIL_NEXT)
        self->topstack->context ^= LC_FAIL_NEXT;
    return 0;
}

/*
    Handle a template parameter at the head of the string.
*/
static int
Tokenizer_handle_template_param(memory_arena_t *a, Tokenizer *self)
{
    // PyObject *stack;

    if (self->topstack->context & LC_TEMPLATE_NAME) {
        if (!(self->topstack->context & (LC_HAS_TEXT | LC_HAS_TEMPLATE))) {
            Tokenizer_fail_route(a, self);
            return 1;
        }
        self->topstack->context ^= LC_TEMPLATE_NAME;
    } else if (self->topstack->context & LC_TEMPLATE_PARAM_VALUE) {
        self->topstack->context ^= LC_TEMPLATE_PARAM_VALUE;
    }
    if (self->topstack->context & LC_TEMPLATE_PARAM_KEY) {
        TokenList *stack = Tokenizer_pop(a, self);
        if (!stack) {
            return 1;
        }
        if (Tokenizer_emit_all(a, self, stack)) {
            return 1;
        }
    } else {
        self->topstack->context |= LC_TEMPLATE_PARAM_KEY;
    }
    TOKEN(psep, TemplateParamSeparator)
    if (Tokenizer_emit(a, self, &psep)) {
        return 1;
    }
    if (Tokenizer_push(a, self, self->topstack->context)) {
        return 1;
    }
    return 0;
}

/*
    Handle a template parameter's value at the head of the string.
*/
static int
Tokenizer_handle_template_param_value(memory_arena_t *a, Tokenizer *self)
{
    TokenList *stack = Tokenizer_pop(a, self);
    if (!stack) {
        return 1;
    }
    if (Tokenizer_emit_all(a, self, stack))
        return 1;
    self->topstack->context ^= LC_TEMPLATE_PARAM_KEY;
    self->topstack->context |= LC_TEMPLATE_PARAM_VALUE;
    TOKEN(tpeql, TemplateParamEquals)
    if (Tokenizer_emit(a, self, &tpeql)) {
        return 1;
    }
    return 0;
}

/*
    Handle the end of a template at the head of the string.
*/
static TokenList *
Tokenizer_handle_template_end(memory_arena_t *a, Tokenizer *self)
{
    if (self->topstack->context & LC_TEMPLATE_NAME) {
        if (!(self->topstack->context & (LC_HAS_TEXT | LC_HAS_TEMPLATE))) {
            return Tokenizer_fail_route(a, self);
        }
    } else if (self->topstack->context & LC_TEMPLATE_PARAM_KEY) {
        TokenList *stack = Tokenizer_pop(a, self);
        if (!stack)
            return NULL;
        if (Tokenizer_emit_all(a, self, stack))
            return NULL;
    }
    self->head++;
    return Tokenizer_pop(a, self);
}

/*
    Handle the separator between an argument's name and default.
*/
static int
Tokenizer_handle_argument_separator(memory_arena_t *a, Tokenizer *self)
{
    self->topstack->context ^= LC_ARGUMENT_NAME;
    self->topstack->context |= LC_ARGUMENT_DEFAULT;
    TOKEN(argsep, ArgumentSeparator)
    if (Tokenizer_emit(a, self, &argsep)) {
        return -1;
    }
    return 0;
}

/*
    Handle the end of an argument at the head of the string.
*/
static TokenList *
Tokenizer_handle_argument_end(memory_arena_t *a, Tokenizer *self)
{
    TokenList *stack = Tokenizer_pop(a, self);

    self->head += 2;
    return stack;
}

/*
    Parse an internal wikilink at the head of the wikicode string.
*/
static int
Tokenizer_parse_wikilink(memory_arena_t *a, Tokenizer *self)
{
    size_t reset;
    // PyObject *extlink, *wikilink, *kwargs;

    reset = self->head + 1;
    self->head += 2;
    // If the wikilink looks like an external link, parse it as such:
    TokenList *extlink = Tokenizer_really_parse_external_link(a, self, 1, NULL);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset + 1;
        // Otherwise, actually parse it as a wikilink:
        TokenList *wikilink = Tokenizer_parse(a, self, LC_WIKILINK_TITLE, 1);
        if (BAD_ROUTE) {
            RESET_ROUTE();
            self->head = reset;
            if (Tokenizer_emit_text(a, self, "[["))
                return 1;
            return 0;
        }
        if (!wikilink)
            return 1;
        TOKEN(wikiopen, WikilinkOpen)
        if (Tokenizer_emit(a, self, &wikiopen))
            return 1;
        if (Tokenizer_emit_all(a, self, wikilink))
            return 1;
        TOKEN(wikiclose, WikilinkClose)
        if (Tokenizer_emit(a, self, &wikiclose))
            return 1;
        return 0;
    }
    if (!extlink) {
        return -1;
    }
    if (self->topstack->context & LC_EXT_LINK_TITLE) {
        // In this exceptional case, an external link that looks like a
        // wikilink inside of an external link is parsed as text:
        self->head = reset;
        if (Tokenizer_emit_text(a, self, "[["))
            return 1;
        return 0;
    }
    if (Tokenizer_emit_text(a, self, "["))
        return 1;

    TOKEN_CTX(el_brackets, ExternalLinkOpen)
    el_brackets.ctx.external_link_open.brackets = true;
    if (Tokenizer_emit_all(a, self, extlink)) {
        return -1;
    }

    TOKEN(el_close, ExternalLinkClose)
    if (Tokenizer_emit(a, self, &el_close)) {
        return -1;
    }

    return 0;
}

/*
    Handle the separator between a wikilink's title and its text.
*/
static int
Tokenizer_handle_wikilink_separator(memory_arena_t *a, Tokenizer *self)
{
    self->topstack->context ^= LC_WIKILINK_TITLE;
    self->topstack->context |= LC_WIKILINK_TEXT;
    TOKEN(wikisep, WikilinkSeparator)
    if (Tokenizer_emit(a, self, &wikisep)) {
        return -1;
    }
    return 0;
}

/*
    Handle the end of a wikilink at the head of the string.
*/
static TokenList *
Tokenizer_handle_wikilink_end(memory_arena_t *a, Tokenizer *self)
{
    TokenList *stack = Tokenizer_pop(a, self);
    self->head += 1;
    return stack;
}

/*
    Parse the URI scheme of a bracket-enclosed external link.
*/
static int
Tokenizer_parse_bracketed_uri_scheme(memory_arena_t *a, Tokenizer *self)
{
    static const char *valid = URISCHEME;

    if (Tokenizer_check_route(self, LC_EXT_LINK_URI) < 0) {
        return 0;
    }

    if (Tokenizer_push(a, self, LC_EXT_LINK_URI)) {
        return 1;
    }

    if (Tokenizer_read(self, 0) == '/' && Tokenizer_read(self, 1) == '/') {
        if (Tokenizer_emit_text(a, self, "//")) {
            return 1;
        }
        self->head += 2;
    } else {
        Textbuffer *buffer = Textbuffer_new(a, &self->text);
        if (!buffer) {
            return 1;
        }
        char this;
        while ((this = Tokenizer_read(self, 0))) {
            size_t i = 0;
            while (true) {
                if (!valid[i]) {
                    goto end_of_loop;
                }
                if (this == valid[i]) {
                    break;
                }
                i++;
            }
            Textbuffer_write(a, buffer, this);
            if (Tokenizer_emit_char(a, self, this)) {
                Textbuffer_dealloc(a, buffer);
                return 1;
            }
            self->head++;
        }
    end_of_loop:
        if (this != ':') {
            Textbuffer_dealloc(a, buffer);
            Tokenizer_fail_route(a, self);
            return 0;
        }
        if (Tokenizer_emit_char(a, self, ':')) {
            Textbuffer_dealloc(a, buffer);
            return 1;
        }
        self->head++;
        bool slashes = Tokenizer_read(self, 0) == '/' && Tokenizer_read(self, 1) == '/';
        if (slashes) {
            if (Tokenizer_emit_text(a, self, "//")) {
                Textbuffer_dealloc(a, buffer);
                return 1;
            }
            self->head += 2;
        }
        if (!is_scheme(buffer->data, buffer->length, slashes)) {
            Tokenizer_fail_route(a, self);
            Textbuffer_dealloc(a, buffer);
            return 0;
        }
    }

    return 0;
}

/*
    Parse the URI scheme of a free (no brackets) external link.
*/
static int
Tokenizer_parse_free_uri_scheme(memory_arena_t *a, Tokenizer *self)
{
    // static const char *valid = URISCHEME;
#define IS_VALID(ch) (isalnum(ch) || ch == '+' || ch == '-' || ch == ".")
    Textbuffer *scheme = Textbuffer_new(a, &self->text);
    if (!scheme) {
        return 1;
    }

    // We have to backtrack through the textbuffer looking for our scheme since
    // it was just parsed as text:
    for (int i = self->topstack->textbuffer->length - 1; i >= 0; i--) {
        char ch = Textbuffer_read(self->topstack->textbuffer, i);
        // Stop at the first non-word character (equivalent to \W in regex)
        if (!isalnum(ch) && ch != '_') {
            break;
        }
        Textbuffer_write(a, scheme, ch);
    }

    Textbuffer_reverse(scheme);

    bool slashes = Tokenizer_read(self, 0) == '/' && Tokenizer_read(self, 1) == '/';

    if (!is_scheme(scheme->data, scheme->length, slashes)) {
        Textbuffer_dealloc(a, scheme);
        FAIL_ROUTE(0);
        return 1;
    }

    uint64_t new_context = self->topstack->context | LC_EXT_LINK_URI;
    if (Tokenizer_check_route(self, new_context) < 0) {
        Textbuffer_dealloc(a, scheme);
        return 1;
    }

    if (Tokenizer_push(a, self, new_context)) {
        Textbuffer_dealloc(a, scheme);
        return 1;
    }

    if (Tokenizer_emit_textbuffer(a, self, scheme)) {
        return 1;
    }

    if (Tokenizer_emit_char(a, self, ':')) {
        return 1;
    }

    if (slashes) {
        if (Tokenizer_emit_text(a, self, "//")) {
            return 1;
        }
        self->head += 2;
    }

    return 0;
}

/*
    Handle text in a free external link, including trailing punctuation.
*/
static int
Tokenizer_handle_free_link_text(
    memory_arena_t *a, Tokenizer *self, int *parens, Textbuffer *tail, char this)
{
#define PUSH_TAIL_BUFFER(tail, error)                                                  \
    do {                                                                               \
        if (tail && tail->length > 0) {                                                \
            if (Textbuffer_concat(a, self->topstack->textbuffer, tail)) {              \
                return error;                                                          \
            }                                                                          \
            if (Textbuffer_reset(tail)) {                                              \
                return error;                                                          \
            }                                                                          \
        }                                                                              \
    } while (0)

    if (this == '(' && !(*parens)) {
        *parens = 1;
        PUSH_TAIL_BUFFER(tail, 1);
    } else if (this == ',' || this == ';' || this == '\\' || this == '.' ||
               this == ':' || this == '!' || this == '?' ||
               (!(*parens) && this == ')')) {
        return Textbuffer_write(a, tail, this);
    } else {
        PUSH_TAIL_BUFFER(tail, 1);
    }
    return Tokenizer_emit_char(a, self, this);
}

/*
    Return whether the current head is the end of a URI.
*/
static int
Tokenizer_is_uri_end(Tokenizer *self, char this, char next)
{
    // Built from Tokenizer_parse()'s end sentinels:
    char after = Tokenizer_read(self, 2);
    uint64_t ctx = self->topstack->context;

    return (!this || this == '\n' || this == '[' || this == ']' || this == '<' ||
            this == '>' || this == '"' || this == ' ' ||
            (this == '\'' && next == '\'') || (this == '|' && ctx & LC_TEMPLATE) ||
            (this == '=' && ctx & (LC_TEMPLATE_PARAM_KEY | LC_HEADING)) ||
            (this == '}' && next == '}' &&
             (ctx & LC_TEMPLATE || (after == '}' && ctx & LC_ARGUMENT))));
}

/*
    Really parse an external link.
*/
static TokenList *
Tokenizer_really_parse_external_link(memory_arena_t *a,
                                     Tokenizer *self,
                                     int brackets,
                                     Textbuffer *extra)
{
    char next;
    int parens = 0;

    if (brackets ? Tokenizer_parse_bracketed_uri_scheme(a, self)
                 : Tokenizer_parse_free_uri_scheme(a, self)) {
        return NULL;
    }
    if (BAD_ROUTE) {
        return NULL;
    }

    char this = Tokenizer_read(self, 0);
    if (!this || this == '\n' || this == ' ' || this == ']') {
        return Tokenizer_fail_route(a, self);
    }
    if (!brackets && this == '[') {
        return Tokenizer_fail_route(a, self);
    }
    while (1) {
        this = Tokenizer_read(self, 0);
        next = Tokenizer_read(self, 1);
        if (this == '&') {
            PUSH_TAIL_BUFFER(extra, NULL);
            if (Tokenizer_parse_entity(a, self)) {
                return NULL;
            }
        } else if (this == '<' && next == '!' && Tokenizer_read(self, 2) == '-' &&
                   Tokenizer_read(self, 3) == '-') {
            PUSH_TAIL_BUFFER(extra, NULL);
            if (Tokenizer_parse_comment(a, self)) {
                return NULL;
            }
        } else if (this == '{' && next == '{' && Tokenizer_CAN_RECURSE(self)) {
            PUSH_TAIL_BUFFER(extra, NULL);
            if (Tokenizer_parse_template_or_argument(a, self)) {
                return NULL;
            }
        } else if (brackets) {
            if (!this || this == '\n') {
                return Tokenizer_fail_route(a, self);
            }
            if (this == ']') {
                return Tokenizer_pop(a, self);
            }
            if (Tokenizer_is_uri_end(self, this, next)) {
                TOKEN_CTX(t, ExternalLinkSeparator)
                t.ctx.external_link_sep.space = (this == ' ');
                Tokenizer_emit(a, self, &t);

                self->topstack->context ^= LC_EXT_LINK_URI;
                self->topstack->context |= LC_EXT_LINK_TITLE;
                return Tokenizer_parse(a, self, 0, false);
            }
            if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else {
            if (Tokenizer_is_uri_end(self, this, next)) {
                if (this == ' ') {
                    if (Textbuffer_write(a, extra, this)) {
                        return NULL;
                    }
                } else {
                    self->head--;
                }
                return Tokenizer_pop(a, self);
            }
            if (Tokenizer_handle_free_link_text(a, self, &parens, extra, this)) {
                return NULL;
            }
        }
        self->head++;
    }
}

/*
    Remove the URI scheme of a new external link from the textbuffer.
*/
static int
Tokenizer_remove_uri_scheme_from_textbuffer(Tokenizer *self, TokenList *link)
{
    self->topstack->textbuffer->length = 0;
    return 0;
}

/*
    Parse an external link at the head of the wikicode string.
*/
static int
Tokenizer_parse_external_link(memory_arena_t *a, Tokenizer *self, bool brackets)
{
#define NOT_A_LINK                                                                     \
    if (!brackets && self->topstack->context & LC_DLTERM) {                            \
        return Tokenizer_handle_dl_term(a, self);                                      \
    }                                                                                  \
    return Tokenizer_emit_char(a, self, Tokenizer_read(self, 0));

    size_t reset = self->head;
    Textbuffer *extra;

    if (self->topstack->context & AGG_NO_EXT_LINKS || !(Tokenizer_CAN_RECURSE(self))) {
        NOT_A_LINK;
    }
    extra = Textbuffer_new(a, &self->text);
    if (!extra) {
        return 1;
    }
    self->head++;
    TokenList *link = Tokenizer_really_parse_external_link(a, self, brackets, extra);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset;
        Textbuffer_dealloc(a, extra);
        NOT_A_LINK;
    }
    if (!link) {
        Textbuffer_dealloc(a, extra);
        return 1;
    }
    if (!brackets) {
        if (Tokenizer_remove_uri_scheme_from_textbuffer(self, link)) {
            Textbuffer_dealloc(a, extra);
            return 1;
        }
    }

    TOKEN_CTX(el_open, ExternalLinkOpen)
    el_open.ctx.external_link_open.brackets = brackets;
    if (Tokenizer_emit(a, self, &el_open)) {
        Textbuffer_dealloc(a, extra);
        return 1;
    }

    if (Tokenizer_emit_all(a, self, link)) {
        Textbuffer_dealloc(a, extra);
        return 1;
    }

    TOKEN(el_close, ExternalLinkClose)
    if (Tokenizer_emit(a, self, &el_close)) {
        Textbuffer_dealloc(a, extra);
        return 1;
    }

    if (extra->length > 0) {
        return Tokenizer_emit_textbuffer(a, self, extra);
    }

    Textbuffer_dealloc(a, extra);
    return 0;
}

/*
    Parse a section heading at the head of the wikicode string.
*/
static int
Tokenizer_parse_heading(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;
    int best = 1, i, context, diff;

    self->global |= GL_HEADING;
    self->head += 1;
    while (Tokenizer_read(self, 0) == '=') {
        best++;
        self->head++;
    }
    context = LC_HEADING_LEVEL_1 << (best > 5 ? 5 : best - 1);
    HeadingData *title_level = (HeadingData *) Tokenizer_parse(a, self, context, 1);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset + best - 1;
        for (i = 0; i < best; i++) {
            if (Tokenizer_emit_char(a, self, '=')) {
                return 1;
            }
        }
        self->global ^= GL_HEADING;
        return 0;
    }
    if (!title_level) {
        return 1;
    }

    TokenList *title = title_level->title;
    size_t level = title_level->level;

    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset + best - 1;
        for (i = 0; i < best; i++) {
            if (Tokenizer_emit_char(a, self, '=')) {
                return 1;
            }
        }
        self->global ^= GL_HEADING;
        return 0;
    }

    if (title->len != 1) {
        return 1;
    }
    if (!level) {
        return 1;
    }
    TOKEN_CTX(heading_open, HeadingStart)
    heading_open.ctx.heading.level = level;
    if (Tokenizer_emit(a, self, &heading_open)) {
        return 1;
    }
    if (level < best) {
        diff = best - level;
        for (i = 0; i < diff; i++) {
            if (Tokenizer_emit_char(a, self, '=')) {
                return 1;
            }
        }
    }
    if (Tokenizer_emit_all(a, self, title)) {
        arena_free(a, title_level);
        return -1;
    }
    TOKEN(h_end, HeadingEnd)
    if (Tokenizer_emit(a, self, &h_end)) {
        return 1;
    }
    self->global ^= GL_HEADING;
    return 0;
}

/*
    Handle the end of a section heading at the head of the string.
*/
static HeadingData *
Tokenizer_handle_heading_end(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;
    int best, i, current, level, diff;
    HeadingData *after, *heading;
    TokenList *stack;

    self->head += 1;
    best = 1;
    while (Tokenizer_read(self, 0) == '=') {
        best++;
        self->head++;
    }
    current = heading_level_from_context(self->topstack->context);
    level = current > best ? (best > 6 ? 6 : best) : (current > 6 ? 6 : current);
    after = (HeadingData *) Tokenizer_parse(a, self, self->topstack->context, 1);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        if (level < best) {
            diff = best - level;
            for (i = 0; i < diff; i++) {
                if (Tokenizer_emit_char(a, self, '=')) {
                    return NULL;
                }
            }
        }
        self->head = reset + best - 1;
    } else {
        if (!after) {
            return NULL;
        }
        for (i = 0; i < best; i++) {
            if (Tokenizer_emit_char(a, self, '=')) {
                // Py_DECREF(after->title);
                arena_free(a, after);
                return NULL;
            }
        }
        if (Tokenizer_emit_all(a, self, after->title)) {
            // Py_DECREF(after->title);
            arena_free(a, after);
            return NULL;
        }
        level = after->level;
        arena_free(a, after);
    }
    stack = Tokenizer_pop(a, self);
    if (!stack) {
        return NULL;
    }
    heading = arena_alloc(a, sizeof(HeadingData));
    if (!heading)
        return NULL;
    heading->title = stack;
    heading->level = level;
    return heading;
}

/*
    Actually parse an HTML entity and ensure that it is valid.
*/
static int
Tokenizer_really_parse_entity(memory_arena_t *a, Tokenizer *self)
{
    int numeric, hexadecimal = 0;

#define FAIL_ROUTE_AND_EXIT()                                                          \
    do {                                                                               \
        Tokenizer_fail_route(a, self);                                                 \
        arena_free(a, text);                                                           \
        return 0;                                                                      \
    } while (0)

    TOKEN(he_start, HTMLEntityStart)
    if (Tokenizer_emit(a, self, &he_start)) {
        return 1;
    }
    self->head++;
    char this = Tokenizer_read(self, 0);
    if (!this) {
        Tokenizer_fail_route(a, self);
        return 0;
    }
    if (this == '#') {
        numeric = 1;
        TOKEN(he_num, HTMLEntityNumeric)
        if (Tokenizer_emit(a, self, &he_num))
            return 1;
        self->head++;
        this = Tokenizer_read(self, 0);
        if (!this) {
            Tokenizer_fail_route(a, self);
            return 0;
        }
        if (this == 'x' || this == 'X') {
            hexadecimal = 1;
            TOKEN(he_hex, HTMLEntityHex)
            if (Tokenizer_emit(a, self, &he_hex))
                return 1;
            self->head++;
        } else {
            hexadecimal = 0;
        }
    } else {
        numeric = hexadecimal = 0;
    }
    const char *valid;
    if (hexadecimal) {
        valid = HEXDIGITS;
    } else if (numeric) {
        valid = DIGITS;
    } else {
        valid = ALPHANUM;
    }
    char *text = arena_calloc(a, MAX_ENTITY_SIZE, sizeof(char));
    if (!text)
        return 1;
    int i = 0;
    int zeroes = 0;
    while (1) {
        this = Tokenizer_read(self, 0);
        if (this == ';') {
            if (i == 0) {
                FAIL_ROUTE_AND_EXIT();
            }
            break;
        }
        if (i == 0 && numeric && this == '0') {
            zeroes++;
            self->head++;
            continue;
        }
        if (i >= MAX_ENTITY_SIZE) {
            FAIL_ROUTE_AND_EXIT();
        }
        if (is_marker(this)) {
            FAIL_ROUTE_AND_EXIT();
        }
        int j = 0;
        while (1) {
            if (!valid[j]) {
                FAIL_ROUTE_AND_EXIT();
            }
            if (this == valid[j]) {
                break;
            }
            j++;
        }
        text[i] = (char) this;
        self->head++;
        i++;
    }
    if (numeric) {
        int test;
        sscanf(text, (hexadecimal ? "%x" : "%d"), &test);
        if (test < 1 || test > 0x10FFFF) {
            FAIL_ROUTE_AND_EXIT();
        }
    }

    // TODO: Place all possible into a comptime hash table;
    // For now, char entities are assumed to be valid.

    if (zeroes) {
        char *buffer = arena_calloc(a, strlen(text) + zeroes + 1, sizeof(char));
        if (!buffer) {
            arena_free(a, text);
            return 1;
        }
        for (i = 0; i < zeroes; i++) {
            strcat(buffer, "0");
        }
        strcat(buffer, text);
        arena_free(a, text);
        text = buffer;
    }
    TOKEN_CTX(txt_tok, Text)
    txt_tok.ctx.data = text;
    if (Tokenizer_emit(a, self, &txt_tok))
        return 1;
    TOKEN(hte_end, HTMLEntityEnd);
    if (Tokenizer_emit(a, self, &hte_end))
        return 1;
    return 0;
}

/*
    Parse an HTML entity at the head of the wikicode string.
*/
static int
Tokenizer_parse_entity(memory_arena_t *a, Tokenizer *self)
{
    // puts("TRACE: enter Tokenizer_parse_entity");
    size_t reset = self->head;

    if (Tokenizer_check_route(self, LC_HTML_ENTITY) < 0) {
        goto on_bad_route;
    }
    if (Tokenizer_push(a, self, LC_HTML_ENTITY)) {
        assert(false);
    }
    if (Tokenizer_really_parse_entity(a, self)) {
        // puts("TRACE: really_parse_entity failed");
        return -1;
    }
    if (BAD_ROUTE) {
    on_bad_route:
        RESET_ROUTE();
        self->head = reset;
        if (Tokenizer_emit_char(a, self, '&')) {
            return -1;
        }
        return 0;
    }
    TokenList *tokenlist = Tokenizer_pop(a, self);
    assert(tokenlist);
    // printf("TRACE: head: %zu, TokenList.len: %zu\n", self->head,
    // tokenlist->len);
    if (Tokenizer_emit_all(a, self, tokenlist))
        return 1;
    return 0;
}

/*
    Parse an HTML comment at the head of the wikicode string.
*/
static int
Tokenizer_parse_comment(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head + 3;
    TokenList *comment;

    self->head += 4;
    if (Tokenizer_push(a, self, 0)) {
        return 1;
    }
    while (1) {
        char this = Tokenizer_read(self, 0);
        if (!this) {
            comment = Tokenizer_pop(a, self);
            self->head = reset;
            return Tokenizer_emit_text(a, self, "<!--");
        }
        if (this == '-' && Tokenizer_read(self, 1) == this &&
            Tokenizer_read(self, 2) == '>') {
            TOKEN(c_start, CommentStart)
            if (Tokenizer_emit_first(a, self, &c_start)) {
                return 1;
            }
            TOKEN(c_end, CommentEnd)
            if (Tokenizer_emit(a, self, &c_end)) {
                return 1;
            }
            comment = Tokenizer_pop(a, self);
            if (!comment) {
                return 1;
            }
            if (Tokenizer_emit_all(a, self, comment)) {
                return 1;
            }
            self->head += 2;
            if (self->topstack->context & LC_FAIL_NEXT) {
                /* _verify_safe() sets this flag while parsing a template or
                   link when it encounters what might be a comment -- we must
                   unset it to let _verify_safe() know it was correct: */
                self->topstack->context ^= LC_FAIL_NEXT;
            }
            return 0;
        }
        if (Tokenizer_emit_char(a, self, this)) {
            return 1;
        }
        self->head++;
    }
}

/*
    Write a pending tag attribute from data to the stack.
*/
static int
Tokenizer_push_tag_buffer(memory_arena_t *a, Tokenizer *self, TagData *data)
{
    // PyObject *tokens, *kwargs, *tmp, *pad_first, *pad_before_eq, *pad_after_eq;

    if (data->context & TAG_QUOTED) {
        TOKEN_CTX(tag_attr_q_token, TagAttrQuote);
        tag_attr_q_token.ctx.tag_attr_quote.quote = data->quoter;
        if (Tokenizer_emit_first(a, self, &tag_attr_q_token))
            return 1;

        TokenList *tokens = Tokenizer_pop(a, self);
        if (!tokens)
            return 1;
        if (Tokenizer_emit_all(a, self, tokens))
            return 1;
    }

    // pad_first = Textbuffer_render(data->pad_first);
    // pad_before_eq = Textbuffer_render(data->pad_before_eq);
    // pad_after_eq = Textbuffer_render(data->pad_after_eq);
    // if (!pad_first || !pad_before_eq || !pad_after_eq) {
    //     return -1;
    // }
    // kwargs = PyDict_New();
    // if (!kwargs) {
    //     return -1;
    // }
    // PyDict_SetItemString(kwargs, "pad_first", pad_first);
    // PyDict_SetItemString(kwargs, "pad_before_eq", pad_before_eq);
    // PyDict_SetItemString(kwargs, "pad_after_eq", pad_after_eq);
    // Py_DECREF(pad_first);
    // Py_DECREF(pad_before_eq);
    // Py_DECREF(pad_after_eq);
    // if (Tokenizer_emit_first_kwargs(self, TagAttrStart, kwargs)) {
    //     return -1;
    // }

    TOKEN(tag_attr_start_tok, TagAttrStart);
    if (Tokenizer_emit_first(a, self, &tag_attr_start_tok))
        return 1;

    TokenList *tokens = Tokenizer_pop(a, self);
    if (!tokens)
        return 1;
    if (Tokenizer_emit_all(a, self, tokens))
        return 1;
    if (TagData_reset_buffers(data))
        return 1;
    return 0;
}

/*
    Handle whitespace inside of an HTML open tag.
*/
static int
Tokenizer_handle_tag_space(memory_arena_t *a, Tokenizer *self, TagData *data, char text)
{
    uint64_t ctx = data->context;
    uint64_t end_of_value =
        (ctx & TAG_ATTR_VALUE && !(ctx & (TAG_QUOTED | TAG_NOTE_QUOTE)));

    if (end_of_value || (ctx & TAG_QUOTED && ctx & TAG_NOTE_SPACE)) {
        if (Tokenizer_push_tag_buffer(a, self, data)) {
            return -1;
        }
        data->context = TAG_ATTR_READY;
    } else if (ctx & TAG_NOTE_SPACE) {
        data->context = TAG_ATTR_READY;
    } else if (ctx & TAG_ATTR_NAME) {
        data->context |= TAG_NOTE_EQUALS;
        if (Textbuffer_write(a, data->pad_before_eq, text)) {
            return -1;
        }
    }
    if (ctx & TAG_QUOTED && !(ctx & TAG_NOTE_SPACE)) {
        if (Tokenizer_emit_char(a, self, text)) {
            return -1;
        }
    } else if (data->context & TAG_ATTR_READY) {
        return Textbuffer_write(a, data->pad_first, text);
    } else if (data->context & TAG_ATTR_VALUE) {
        return Textbuffer_write(a, data->pad_after_eq, text);
    }
    return 0;
}

/*
    Handle regular text inside of an HTML open tag.
*/
static int
Tokenizer_handle_tag_text(memory_arena_t *a, Tokenizer *self, char text)
{
    char next = Tokenizer_read(self, 1);

    if (!is_marker(text) || !Tokenizer_CAN_RECURSE(self)) {
        return Tokenizer_emit_char(a, self, text);
    } else if (text == next && next == '{') {
        return Tokenizer_parse_template_or_argument(a, self);
    } else if (text == next && next == '[') {
        return Tokenizer_parse_wikilink(a, self);
    } else if (text == '<') {
        return Tokenizer_parse_tag(a, self);
    }
    return Tokenizer_emit_char(a, self, text);
}

/*
    Handle all sorts of text data inside of an HTML open tag.
*/
static int
Tokenizer_handle_tag_data(memory_arena_t *a, Tokenizer *self, TagData *data, char chunk)
{
    if (data->context & TAG_NAME) {
        int first_time = !(data->context & TAG_NOTE_SPACE);
        if (is_marker(chunk) || (isspace(chunk) && first_time)) {
            // Tags must start with text, not spaces
            Tokenizer_fail_route(a, self);
            return 0;
        } else if (first_time) {
            data->context |= TAG_NOTE_SPACE;
        } else if (isspace(chunk)) {
            data->context = TAG_ATTR_READY;
            return Tokenizer_handle_tag_space(a, self, data, chunk);
        }
    } else if (isspace(chunk)) {
        return Tokenizer_handle_tag_space(a, self, data, chunk);
    } else if (data->context & TAG_NOTE_SPACE) {
        if (data->context & TAG_QUOTED) {
            data->context = TAG_ATTR_VALUE;
            Tokenizer_memoize_bad_route(a, self);
            Tokenizer_pop(a, self);
            self->head = data->reset - 1; // Will be auto-incremented
        } else {
            Tokenizer_fail_route(a, self);
        }
        return 0;
    } else if (data->context & TAG_ATTR_READY) {
        data->context = TAG_ATTR_NAME;
        if (Tokenizer_push(a, self, LC_TAG_ATTR)) {
            return -1;
        }
    } else if (data->context & TAG_ATTR_NAME) {
        if (chunk == '=') {
            data->context = TAG_ATTR_VALUE | TAG_NOTE_QUOTE;
            TOKEN(t_attr_eql, TagAttrEquals)
            if (Tokenizer_emit(a, self, &t_attr_eql)) {
                return -1;
            }
            return 0;
        }
        if (data->context & TAG_NOTE_EQUALS) {
            if (Tokenizer_push_tag_buffer(a, self, data)) {
                return -1;
            }
            data->context = TAG_ATTR_NAME;
            if (Tokenizer_push(a, self, LC_TAG_ATTR)) {
                return -1;
            }
        }
    } else { // data->context & TAG_ATTR_VALUE assured
        int escaped = (Tokenizer_read_backwards(self, 1) == '\\' &&
                       Tokenizer_read_backwards(self, 2) != '\\');
        if (data->context & TAG_NOTE_QUOTE) {
            data->context ^= TAG_NOTE_QUOTE;
            if ((chunk == '"' || chunk == '\'') && !escaped) {
                data->context |= TAG_QUOTED;
                data->quoter = chunk;
                data->reset = self->head;
                if (Tokenizer_check_route(self, self->topstack->context) < 0) {
                    RESET_ROUTE();
                    data->context = TAG_ATTR_VALUE;
                    self->head--;
                } else if (Tokenizer_push(a, self, self->topstack->context)) {
                    return -1;
                }
                return 0;
            }
        } else if (data->context & TAG_QUOTED) {
            if (chunk == data->quoter && !escaped) {
                data->context |= TAG_NOTE_SPACE;
                return 0;
            }
        }
    }
    return Tokenizer_handle_tag_text(a, self, chunk);
}

/*
    Handle the closing of a open tag (<foo>).
*/
static int
Tokenizer_handle_tag_close_open(memory_arena_t *a,
                                Tokenizer *self,
                                TagData *data,
                                TokenType tok_type)
{
    if (data->context & (TAG_ATTR_NAME | TAG_ATTR_VALUE)) {
        if (Tokenizer_push_tag_buffer(a, self, data))
            return 1;
    }

    // TODO: Set Padding from data->pad_first.

    TOKEN(cls_tok, tok_type);
    if (Tokenizer_emit(a, self, &cls_tok))
        return 1;

    self->head++;
    return 0;
}

/*
    Handle the opening of a closing tag (</foo>).
*/
static int
Tokenizer_handle_tag_open_close(memory_arena_t *a, Tokenizer *self)
{
    TOKEN(tag_open_close, TagOpenClose)
    if (Tokenizer_emit(a, self, &tag_open_close)) {
        return 1;
    }
    if (Tokenizer_push(a, self, LC_TAG_CLOSE)) {
        return 1;
    }
    self->head++;
    return 0;
}

/*
    Handle the ending of a closing tag (</foo>).
*/
static void *
Tokenizer_handle_tag_close_close(Tokenizer *self)
{
    puts("Tokenizer_handle_tag_close_close not implemented");
    exit(1);
    return NULL;

    // PyObject *closing, *first, *so, *sc;
    // int valid = 1;

    // closing = Tokenizer_pop(self);
    // if (!closing) {
    //     return NULL;
    // }
    // if (PyList_GET_SIZE(closing) != 1) {
    //     valid = 0;
    // } else {
    //     first = PyList_GET_ITEM(closing, 0);
    //     switch (PyObject_IsInstance(first, Text)) {
    //     case 0:
    //         valid = 0;
    //         break;
    //     case 1: {
    //         so = strip_tag_name(first, 1);
    //         sc = strip_tag_name(PyList_GET_ITEM(self->topstack->stack, 1), 1);
    //         if (so && sc) {
    //             if (PyUnicode_Compare(so, sc)) {
    //                 valid = 0;
    //             }
    //             Py_DECREF(so);
    //             Py_DECREF(sc);
    //             break;
    //         }
    //         Py_XDECREF(so);
    //         Py_XDECREF(sc);
    //     }
    //     case -1:
    //         Py_DECREF(closing);
    //         return NULL;
    //     }
    // }
    // if (!valid) {
    //     Py_DECREF(closing);
    //     return Tokenizer_fail_route(self);
    // }
    // if (Tokenizer_emit_all(self, closing)) {
    //     Py_DECREF(closing);
    //     return NULL;
    // }
    // Py_DECREF(closing);
    // if (Tokenizer_emit(self, TagCloseClose)) {
    //     return NULL;
    // }
    // return Tokenizer_pop(self);
}

/*
    Handle the body of an HTML tag that is parser-blacklisted.
*/
static TokenList *
Tokenizer_handle_blacklisted_tag(memory_arena_t *a, Tokenizer *self)
{
    // puts("Tokenizer_handle_blacklisted_tag open");
    // exit(1);
    // return NULL;

    // Textbuffer *buffer;
    // PyObject *buf_tmp, *end_tag, *start_tag;
    // Py_UCS4 this, next;
    // Py_ssize_t reset;
    // int cmp;

    while (1) {
        char this = Tokenizer_read(self, 0);
        char next = Tokenizer_read(self, 1);
        if (!this) {
            return Tokenizer_fail_route(a, self);
        } else if (this == '<' && next == '/') {
            self->head += 2;
            size_t reset = self->head - 1;
            Textbuffer *buffer = Textbuffer_new(a, &self->text);
            if (!buffer) {
                return NULL;
            }
            while ((this = Tokenizer_read(self, 0)), 1) {
                if (this == '>') {
                    // buf_tmp = Textbuffer_render(buffer);
                    // if (!buf_tmp) {
                    //     return NULL;
                    // }
                    // end_tag = strip_tag_name(buf_tmp, 0);
                    // Py_DECREF(buf_tmp);
                    // if (!end_tag) {
                    //     return NULL;
                    // }
                    // start_tag =
                    //     strip_tag_name(PyList_GET_ITEM(self->topstack->stack, 1), 1);
                    // if (!start_tag) {
                    //     return NULL;
                    // }
                    // cmp = PyUnicode_Compare(start_tag, end_tag);
                    // Py_DECREF(end_tag);
                    // Py_DECREF(start_tag);
                    // if (cmp) {
                    //     goto no_matching_end;
                    // }
                    // if (Tokenizer_emit(a, self, TagOpenClose)) {
                    //     return NULL;
                    // }
                    // if (Tokenizer_emit_textbuffer(a, self, buffer)) {
                    //     return NULL;
                    // }
                    // if (Tokenizer_emit(a, self, TagCloseClose)) {
                    //     return NULL;
                    // }
                    // return Tokenizer_pop(a, self);
                }
                if (!this || this == '\n') {
                no_matching_end:
                    Textbuffer_dealloc(a, buffer);
                    self->head = reset;
                    if (Tokenizer_emit_text(a, self, "</"))
                        return NULL;
                    break;
                }
                Textbuffer_write(a, buffer, this);
                self->head++;
            }
        } else if (this == '&') {
            if (Tokenizer_parse_entity(a, self)) {
                return NULL;
            }
        } else if (Tokenizer_emit_char(a, self, this)) {
            return NULL;
        }
        self->head++;
    }
}

/*
    Handle the end of an implicitly closing single-only HTML tag.
*/
static void *
Tokenizer_handle_single_only_tag_end(Tokenizer *self)
{
    puts("Tokenizer_handle_single_only_tag_end not implemented");
    exit(1);
    return NULL;

    // PyObject *top, *padding, *kwargs;

    // top = PyObject_CallMethod(self->topstack->stack, "pop", NULL);
    // if (!top) {
    //     return NULL;
    // }
    // padding = PyObject_GetAttrString(top, "padding");
    // Py_DECREF(top);
    // if (!padding) {
    //     return NULL;
    // }
    // kwargs = PyDict_New();
    // if (!kwargs) {
    //     Py_DECREF(padding);
    //     return NULL;
    // }
    // PyDict_SetItemString(kwargs, "padding", padding);
    // PyDict_SetItemString(kwargs, "implicit", Py_True);
    // Py_DECREF(padding);
    // if (Tokenizer_emit_kwargs(self, TagCloseSelfclose, kwargs)) {
    //     return NULL;
    // }
    // self->head--; // Offset displacement done by handle_tag_close_open
    // return Tokenizer_pop(self);
}

/*
    Handle the stream end when inside a single-supporting HTML tag.
*/
static TokenList *
Tokenizer_handle_single_tag_end(Tokenizer *self)
{
    puts("Tokenizer_handle_single_tag_end");
    exit(1);
    return NULL;

    // PyObject *token = 0, *padding, *kwargs;
    // Py_ssize_t len, index;
    // int depth = 1, is_instance;

    // len = PyList_GET_SIZE(self->topstack->stack);
    // for (index = 2; index < len; index++) {
    //     token = PyList_GET_ITEM(self->topstack->stack, index);
    //     is_instance = PyObject_IsInstance(token, TagOpenOpen);
    //     if (is_instance == -1) {
    //         return NULL;
    //     } else if (is_instance == 1) {
    //         depth++;
    //     }
    //     is_instance = PyObject_IsInstance(token, TagCloseOpen);
    //     if (is_instance == -1) {
    //         return NULL;
    //     } else if (is_instance == 1) {
    //         depth--;
    //         if (depth == 0) {
    //             break;
    //         }
    //     }
    //     is_instance = PyObject_IsInstance(token, TagCloseSelfclose);
    //     if (is_instance == -1) {
    //         return NULL;
    //     } else if (is_instance == 1) {
    //         depth--;
    //         if (depth == 0) { // Should never happen
    //             return NULL;
    //         }
    //     }
    // }
    // if (!token || depth > 0) {
    //     return NULL;
    // }
    // padding = PyObject_GetAttrString(token, "padding");
    // if (!padding) {
    //     return NULL;
    // }
    // kwargs = PyDict_New();
    // if (!kwargs) {
    //     Py_DECREF(padding);
    //     return NULL;
    // }
    // PyDict_SetItemString(kwargs, "padding", padding);
    // PyDict_SetItemString(kwargs, "implicit", Py_True);
    // Py_DECREF(padding);
    // token = PyObject_Call(TagCloseSelfclose, NOARGS, kwargs);
    // Py_DECREF(kwargs);
    // if (!token) {
    //     return NULL;
    // }
    // if (PyList_SetItem(self->topstack->stack, index, token)) {
    //     Py_DECREF(token);
    //     return NULL;
    // }
    // return Tokenizer_pop(self);
}

/*
    Actually parse an HTML tag, starting with the open (<foo>).
*/
static TokenList *
Tokenizer_really_parse_tag(memory_arena_t *a, Tokenizer *self)
{
    TagData *data = TagData_new(a, &self->text);

    if (!data) {
        return NULL;
    }
    if (Tokenizer_check_route(self, LC_TAG_OPEN) < 0) {
        TagData_dealloc(a, data);
        return NULL;
    }
    if (Tokenizer_push(a, self, LC_TAG_OPEN)) {
        TagData_dealloc(a, data);
        return NULL;
    }
    TOKEN(tag_open_open, TagOpenOpen);
    if (Tokenizer_emit(a, self, &tag_open_open)) {
        TagData_dealloc(a, data);
        return NULL;
    }
    while (1) {
        char this = Tokenizer_read(self, 0);
        char next = Tokenizer_read(self, 1);
        int can_exit = (!(data->context & (TAG_QUOTED | TAG_NAME)) ||
                        data->context & TAG_NOTE_SPACE);
        if (!this) {
            if (self->topstack->context & LC_TAG_ATTR) {
                if (data->context & TAG_QUOTED) {
                    // Unclosed attribute quote: reset, don't die
                    data->context = TAG_ATTR_VALUE;
                    Tokenizer_memoize_bad_route(a, self);
                    Tokenizer_pop(a, self);
                    self->head = data->reset;
                    continue;
                }
                Tokenizer_pop(a, self);
            }
            TagData_dealloc(a, data);
            return Tokenizer_fail_route(a, self);
        } else if (this == '>' && can_exit) {
            if (Tokenizer_handle_tag_close_open(a, self, data, TagCloseOpen)) {
                TagData_dealloc(a, data);
                return NULL;
            }
            TagData_dealloc(a, data);
            self->topstack->context = LC_TAG_BODY;
            if (self->topstack == NULL || self->topstack->tokenlist == NULL ||
                self->topstack->tokenlist->len <= 1) {
                return NULL;
            }
            Token token = self->topstack->tokenlist->tokens[1];
            if (token.type != Text)
                return NULL;
            char *text = token.ctx.data;
            if (is_single_only(text, strlen(text))) {
                return Tokenizer_handle_single_only_tag_end(self);
            }
            if (is_parsable(text, strlen(text))) {
                return Tokenizer_parse(a, self, 0, 0);
            }
            return Tokenizer_handle_blacklisted_tag(a, self);
        } else if (this == '/' && next == '>' && can_exit) {
            if (Tokenizer_handle_tag_close_open(a, self, data, TagCloseSelfclose)) {
                TagData_dealloc(a, data);
                return NULL;
            }
            TagData_dealloc(a, data);
            return Tokenizer_pop(a, self);
        } else {
            if (Tokenizer_handle_tag_data(a, self, data, this) || BAD_ROUTE) {
                TagData_dealloc(a, data);
                return NULL;
            }
        }
        self->head++;
    }
}

/*
    Handle the (possible) start of an implicitly closing single tag.
*/
static int
Tokenizer_handle_invalid_tag_start(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head + 1, pos = 0;
    // Textbuffer *buf;
    // PyObject *name, *tag;
    // Py_UCS4 this;

    self->head += 2;
    Textbuffer *buf = Textbuffer_new(a, &self->text);
    if (!buf)
        return 1;

    while (true) {
        char this = Tokenizer_read(self, pos);
        if (isspace(this) || is_marker(this)) {
            if (!is_single_only(buf->data, buf->length))
                FAIL_ROUTE(0);
            break;
        }
        Textbuffer_write(a, buf, this);
        pos++;
    }
    Textbuffer_dealloc(a, buf);
    TokenList *tag;
    if (!BAD_ROUTE) {
        tag = Tokenizer_really_parse_tag(a, self);
    }
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset;
        return Tokenizer_emit_text(a, self, "</");
    }
    if (!tag) {
        return 1;
    }
    // TODO: Figure this out.
    // Set invalid = True flag of TagOpenOpen
    // if (PyObject_SetAttrString(PyList_GET_ITEM(tag, 0), "invalid", Py_True)) {
    //     return -1;
    // }
    if (Tokenizer_emit_all(a, self, tag))
        return 1;
    return 0;
}

/*
    Parse an HTML tag at the head of the wikicode string.
*/
static int
Tokenizer_parse_tag(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;

    self->head++;
    TokenList *tag = Tokenizer_really_parse_tag(a, self);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset;
        return Tokenizer_emit_char(a, self, '<');
    }
    if (!tag)
        return 1;
    if (Tokenizer_emit_all(a, self, tag))
        return 1;
    return 0;
}

/*
    Write the body of a tag and the tokens that should surround it.
*/
static int
Tokenizer_emit_style_tag(Tokenizer *self,
                         const char *tag,
                         const char *ticks,
                         TokenList *body)
{
    printf("TRACE STYLE: body %lu tokens\n", body->len);
    printf("TRACE STYLE: tag: %s, ticks: %s\n", tag, ticks);

    puts("Tokenizer_emit_style_tag not implemented");
    exit(1);
    return 1;

    // PyObject *markup, *kwargs;

    // markup = PyUnicode_FromString(ticks);
    // if (!markup) {
    //     return -1;
    // }
    // kwargs = PyDict_New();
    // if (!kwargs) {
    //     Py_DECREF(markup);
    //     return -1;
    // }
    // PyDict_SetItemString(kwargs, "wiki_markup", markup);
    // Py_DECREF(markup);
    // if (Tokenizer_emit_kwargs(self, TagOpenOpen, kwargs)) {
    //     return -1;
    // }
    // if (Tokenizer_emit_text(self, tag)) {
    //     return -1;
    // }
    // if (Tokenizer_emit(self, TagCloseOpen)) {
    //     return -1;
    // }
    // if (Tokenizer_emit_all(self, body)) {
    //     return -1;
    // }
    // Py_DECREF(body);
    // if (Tokenizer_emit(self, TagOpenClose)) {
    //     return -1;
    // }
    // if (Tokenizer_emit_text(self, tag)) {
    //     return -1;
    // }
    // if (Tokenizer_emit(self, TagCloseClose)) {
    //     return -1;
    // }
    // return 0;
}

/*
    Parse wiki-style italics.
*/
static int
Tokenizer_parse_italics(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;

    TokenList *stack = Tokenizer_parse(a, self, LC_STYLE_ITALICS, 1);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset;
        if (BAD_ROUTE_CONTEXT & LC_STYLE_PASS_AGAIN) {
            stack =
                Tokenizer_parse(a, self, LC_STYLE_ITALICS | LC_STYLE_SECOND_PASS, 1);
            if (BAD_ROUTE) {
                RESET_ROUTE();
                self->head = reset;
                return Tokenizer_emit_text(a, self, "''");
            }
        } else {
            return Tokenizer_emit_text(a, self, "''");
        }
    }
    if (!stack)
        return 1;

    TOKEN(italics, ItalicOpen)
    if (Tokenizer_emit(a, self, &italics))
        return 1;
    if (Tokenizer_emit_all(a, self, stack))
        return 1;
    TOKEN(italics_close, ItalicClose)
    if (Tokenizer_emit(a, self, &italics_close))
        return 1;
    return 0;
}

/*
    Parse wiki-style bold.
*/
static int
Tokenizer_parse_bold(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;

    TokenList *stack = Tokenizer_parse(a, self, LC_STYLE_BOLD, 1);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset;
        if (self->topstack->context & LC_STYLE_SECOND_PASS) {
            return Tokenizer_emit_char(a, self, '\'');
        }
        if (self->topstack->context & LC_STYLE_ITALICS) {
            self->topstack->context |= LC_STYLE_PASS_AGAIN;
            return Tokenizer_emit_text(a, self, "'''");
        }
        if (Tokenizer_emit_char(a, self, '\'')) {
            return -1;
        }
        return Tokenizer_parse_italics(a, self);
    }
    if (!stack)
        return -1;

    TOKEN(bold, BoldOpen)
    if (Tokenizer_emit(a, self, &bold))
        return 1;
    if (Tokenizer_emit_all(a, self, stack))
        return 1;
    TOKEN(bold_close, BoldClose)
    if (Tokenizer_emit(a, self, &bold_close))
        return 1;
    return 0;
}

/*
    Parse wiki-style italics and bold together (i.e., five ticks).
*/
static int
Tokenizer_parse_italics_and_bold(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;
    TOKEN(italic_open, ItalicOpen)
    TOKEN(italic_close, ItalicClose)
    TOKEN(bold_open, BoldOpen)
    TOKEN(bold_close, BoldClose)

    TokenList *stack = Tokenizer_parse(a, self, LC_STYLE_BOLD, 1);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset;
        stack = Tokenizer_parse(a, self, LC_STYLE_ITALICS, 1);
        if (BAD_ROUTE) {
            RESET_ROUTE();
            self->head = reset;
            return Tokenizer_emit_text(a, self, "'''''");
        }
        if (!stack) {
            return -1;
        }
        reset = self->head;
        TokenList *stack2 = Tokenizer_parse(a, self, LC_STYLE_BOLD, 1);
        if (BAD_ROUTE) {
            RESET_ROUTE();
            self->head = reset;
            if (Tokenizer_emit_text(a, self, "'''")) {
                return 1;
            }
            if (Tokenizer_emit(a, self, &italic_open))
                return 1;
            if (Tokenizer_emit_all(a, self, stack))
                return 1;
            if (Tokenizer_emit(a, self, &italic_close))
                return 1;
            return 0;
        }
        if (!stack2) {
            return 1;
        }
        if (Tokenizer_push(a, self, 0)) {
            return 1;
        }

        if (Tokenizer_emit(a, self, &italic_open))
            return 1;
        if (Tokenizer_emit_all(a, self, stack))
            return 1;
        if (Tokenizer_emit(a, self, &italic_close))
            return 1;

        if (Tokenizer_emit_all(a, self, stack2)) {
            return 1;
        }

        stack2 = Tokenizer_pop(a, self);
        if (!stack2) {
            return 1;
        }

        if (Tokenizer_emit(a, self, &italic_open))
            return 1;
        if (Tokenizer_emit_all(a, self, stack2))
            return 1;
        if (Tokenizer_emit(a, self, &italic_close))
            return 1;
        return 0;
    }
    if (!stack) {
        return 1;
    }
    reset = self->head;
    TokenList *stack2 = Tokenizer_parse(a, self, LC_STYLE_ITALICS, 1);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        self->head = reset;
        if (Tokenizer_emit_text(a, self, "''")) {
            return 1;
        }
        if (Tokenizer_emit(a, self, &bold_open))
            return 1;
        if (Tokenizer_emit_all(a, self, stack))
            return 1;
        if (Tokenizer_emit(a, self, &bold_close))
            return 1;
        return 0;
    }
    if (!stack2) {
        return 1;
    }
    if (Tokenizer_push(a, self, 0)) {
        return 1;
    }

    if (Tokenizer_emit(a, self, &bold_open))
        return 1;
    if (Tokenizer_emit_all(a, self, stack))
        return 1;
    if (Tokenizer_emit(a, self, &bold_close))
        return 1;

    if (Tokenizer_emit_all(a, self, stack2)) {
        return 1;
    }
    stack2 = Tokenizer_pop(a, self);
    if (!stack2) {
        return 1;
    }

    if (Tokenizer_emit(a, self, &italic_open))
        return 1;
    if (Tokenizer_emit_all(a, self, stack2))
        return 1;
    if (Tokenizer_emit(a, self, &italic_close))
        return 1;
    return 0;
}

/*
    Parse wiki-style formatting (''/''' for italics/bold).
*/
static TokenList *
Tokenizer_parse_style(memory_arena_t *a, Tokenizer *self)
{
    uint64_t context = self->topstack->context, ticks = 2, i;

    self->head += 2;
    while (Tokenizer_read(self, 0) == '\'') {
        self->head++;
        ticks++;
    }
    if (ticks > 5) {
        for (i = 0; i < ticks - 5; i++) {
            if (Tokenizer_emit_char(a, self, '\'')) {
                return NULL;
            }
        }
        ticks = 5;
    } else if (ticks == 4) {
        if (Tokenizer_emit_char(a, self, '\'')) {
            return NULL;
        }
        ticks = 3;
    }
    if ((context & LC_STYLE_ITALICS && (ticks == 2 || ticks == 5)) ||
        (context & LC_STYLE_BOLD && (ticks == 3 || ticks == 5))) {
        if (ticks == 5) {
            self->head -= context & LC_STYLE_ITALICS ? 3 : 2;
        }
        return Tokenizer_pop(a, self);
    }
    if (!Tokenizer_CAN_RECURSE(self)) {
        if (ticks == 3) {
            if (context & LC_STYLE_SECOND_PASS) {
                if (Tokenizer_emit_char(a, self, '\'')) {
                    return NULL;
                }
                return Tokenizer_pop(a, self);
            }
            if (context & LC_STYLE_ITALICS) {
                self->topstack->context |= LC_STYLE_PASS_AGAIN;
            }
        }
        for (i = 0; i < ticks; i++) {
            if (Tokenizer_emit_char(a, self, '\'')) {
                return NULL;
            }
        }
    } else if (ticks == 2) {
        if (Tokenizer_parse_italics(a, self)) {
            return NULL;
        }
    } else if (ticks == 3) {
        switch (Tokenizer_parse_bold(a, self)) {
        case 1:
            return Tokenizer_pop(a, self);
        case -1:
            return NULL;
        }
    } else {
        if (Tokenizer_parse_italics_and_bold(a, self)) {
            return NULL;
        }
    }
    self->head--;
    return NULL;
}

/*
    Handle a list marker at the head (#, *, ;, :).
*/
static int
Tokenizer_handle_list_marker(memory_arena_t *a, Tokenizer *self)
{
    char c = Tokenizer_read(self, 0);

    if (c == ';')
        self->topstack->context |= LC_DLTERM;

    TokenType tt;
    switch (c) {
    case ':':
        tt = DescriptionItem;
        break;
    case ';':
        tt = DescriptionTerm;
        break;
    case '#':
        tt = OrderedListItem;
        break;
    case '*':
        tt = UnorderedListItem;
        break;
    default: {
        printf("List marker %c found\n", c);
        assert(false && "Unexpected list marker");
    }
    }

    TOKEN(list_marker, tt);
    if (Tokenizer_emit(a, self, &list_marker))
        return 1;
    return 0;
}

/*
    Handle a wiki-style list (#, *, ;, :).
*/
static int
Tokenizer_handle_list(memory_arena_t *a, Tokenizer *self)
{
    char marker = Tokenizer_read(self, 1);

    if (Tokenizer_handle_list_marker(a, self)) {
        return -1;
    }
    while (marker == '#' || marker == '*' || marker == ';' || marker == ':') {
        self->head++;
        if (Tokenizer_handle_list_marker(a, self)) {
            return -1;
        }
        marker = Tokenizer_read(self, 1);
    }
    return 0;
}

/*
    Handle a wiki-style horizontal rule (----) in the string.
*/
static int
Tokenizer_handle_hr(memory_arena_t *a, Tokenizer *self)
{
    // Textbuffer *buffer = Textbuffer_new(&self->text);
    // assert(buffer);
    int i;

    self->head += 3;
    // for (i = 0; i < 4; i++) {
    //     if (Textbuffer_write(buffer, '-'))
    //         return 1;
    // }
    while (Tokenizer_read(self, 1) == '-') {
        // if (Textbuffer_write(buffer, '-'))
        //     return 1;
        self->head++;
    }
    // char *markup = Textbuffer_export(buffer);
    // assert(markup);
    // Textbuffer_dealloc(buffer);

    TOKEN(horizontal_rule, HR)
    if (Tokenizer_emit(a, self, &horizontal_rule))
        return 1;
    return 0;
}

/*
    Handle the term in a description list ('foo' in ';foo:bar').
*/
static int
Tokenizer_handle_dl_term(memory_arena_t *a, Tokenizer *self)
{
    self->topstack->context ^= LC_DLTERM;
    if (Tokenizer_read(self, 0) == ':') {
        return Tokenizer_handle_list_marker(a, self);
    }
    return Tokenizer_emit_char(a, self, '\n');
}

/*
    Emit a table tag.
*/
static int
Tokenizer_emit_table_tag(Tokenizer *self,
                         const char *open_open_markup,
                         const char *tag,
                         void *style,
                         void *padding,
                         const char *close_open_markup,
                         void *contents,
                         const char *open_close_markup)
{
    puts("emit table tag not implemented");
    exit(1);
    return 0;

    // PyObject *open_open_kwargs, *open_open_markup_unicode, *close_open_kwargs,
    //     *close_open_markup_unicode, *open_close_kwargs,
    //     *open_close_markup_unicode;

    // open_open_kwargs = PyDict_New();
    // if (!open_open_kwargs) {
    //     goto fail_decref_all;
    // }
    // open_open_markup_unicode = PyUnicode_FromString(open_open_markup);
    // if (!open_open_markup_unicode) {
    //     Py_DECREF(open_open_kwargs);
    //     goto fail_decref_all;
    // }
    // PyDict_SetItemString(open_open_kwargs, "wiki_markup",
    // open_open_markup_unicode); Py_DECREF(open_open_markup_unicode); if
    // (Tokenizer_emit_kwargs(self, TagOpenOpen, open_open_kwargs)) {
    //     goto fail_decref_all;
    // }
    // if (Tokenizer_emit_text(self, tag)) {
    //     goto fail_decref_all;
    // }

    // if (style) {
    //     if (Tokenizer_emit_all(self, style)) {
    //         goto fail_decref_all;
    //     }
    //     Py_DECREF(style);
    // }

    // close_open_kwargs = PyDict_New();
    // if (!close_open_kwargs) {
    //     goto fail_decref_padding_contents;
    // }
    // if (close_open_markup && strlen(close_open_markup) != 0) {
    //     close_open_markup_unicode = PyUnicode_FromString(close_open_markup);
    //     if (!close_open_markup_unicode) {
    //         Py_DECREF(close_open_kwargs);
    //         goto fail_decref_padding_contents;
    //     }
    //     PyDict_SetItemString(
    //         close_open_kwargs, "wiki_markup", close_open_markup_unicode);
    //     Py_DECREF(close_open_markup_unicode);
    // }
    // PyDict_SetItemString(close_open_kwargs, "padding", padding);
    // Py_DECREF(padding);
    // if (Tokenizer_emit_kwargs(self, TagCloseOpen, close_open_kwargs)) {
    //     goto fail_decref_contents;
    // }

    // if (contents) {
    //     if (Tokenizer_emit_all(self, contents)) {
    //         goto fail_decref_contents;
    //     }
    //     Py_DECREF(contents);
    // }

    // open_close_kwargs = PyDict_New();
    // if (!open_close_kwargs) {
    //     return -1;
    // }
    // open_close_markup_unicode = PyUnicode_FromString(open_close_markup);
    // if (!open_close_markup_unicode) {
    //     Py_DECREF(open_close_kwargs);
    //     return -1;
    // }
    // PyDict_SetItemString(open_close_kwargs, "wiki_markup",
    // open_close_markup_unicode); Py_DECREF(open_close_markup_unicode); if
    // (Tokenizer_emit_kwargs(self, TagOpenClose, open_close_kwargs)) {
    //     return -1;
    // }
    // if (Tokenizer_emit_text(self, tag)) {
    //     return -1;
    // }
    // if (Tokenizer_emit(self, TagCloseClose)) {
    //     return -1;
    // }
    // return 0;

fail_decref_all:
fail_decref_padding_contents:
fail_decref_contents:
    return 1;
}

/*
    Handle style attributes for a table until an ending token.
*/
static TokenList *
Tokenizer_handle_table_style(Tokenizer *self, char end_token)
{
    puts("handle table style not impl");
    exit(1);
    return NULL;

    // TagData *data = TagData_new(&self->text);
    // PyObject *padding, *trash;
    // Py_UCS4 this;
    // int can_exit;

    // if (!data) {
    //     return NULL;
    // }
    // data->context = TAG_ATTR_READY;

    // while (1) {
    //     this = Tokenizer_read(self, 0);
    //     can_exit = (!(data->context & TAG_QUOTED) || data->context &
    //     TAG_NOTE_SPACE); if (this == end_token && can_exit) {
    //         if (data->context & (TAG_ATTR_NAME | TAG_ATTR_VALUE)) {
    //             if (Tokenizer_push_tag_buffer(self, data)) {
    //                 TagData_dealloc(data);
    //                 return NULL;
    //             }
    //         }
    //         if (Py_UNICODE_ISSPACE(this)) {
    //             Textbuffer_write(data->pad_first, this);
    //         }
    //         padding = Textbuffer_render(data->pad_first);
    //         TagData_dealloc(data);
    //         if (!padding) {
    //             return NULL;
    //         }
    //         return padding;
    //     } else if (!this || this == end_token) {
    //         if (self->topstack->context & LC_TAG_ATTR) {
    //             if (data->context & TAG_QUOTED) {
    //                 // Unclosed attribute quote: reset, don't die
    //                 data->context = TAG_ATTR_VALUE;
    //                 Tokenizer_memoize_bad_route(self);
    //                 trash = Tokenizer_pop(self);
    //                 Py_XDECREF(trash);
    //                 self->head = data->reset;
    //                 continue;
    //             }
    //             trash = Tokenizer_pop(self);
    //             Py_XDECREF(trash);
    //         }
    //         TagData_dealloc(data);
    //         return Tokenizer_fail_route(self);
    //     } else {
    //         if (Tokenizer_handle_tag_data(self, data, this) || BAD_ROUTE) {
    //             TagData_dealloc(data);
    //             return NULL;
    //         }
    //     }
    //     self->head++;
    // }
}

/*
    Parse a wikicode table by starting with the first line.
*/
static int
Tokenizer_parse_table(memory_arena_t *a, Tokenizer *self)
{
    size_t reset = self->head;
    void *style, *padding, *trash;
    void *table = NULL;
    StackIdent restore_point;
    self->head += 2;

    if (Tokenizer_check_route(self, LC_TABLE_OPEN) < 0) {
        goto on_bad_route;
    }
    if (Tokenizer_push(a, self, LC_TABLE_OPEN)) {
        return -1;
    }
    padding = Tokenizer_handle_table_style(self, '\n');
    if (BAD_ROUTE) {
    on_bad_route:
        RESET_ROUTE();
        self->head = reset;
        if (Tokenizer_emit_char(a, self, '{')) {
            return -1;
        }
        return 0;
    }
    if (!padding) {
        return -1;
    }
    style = Tokenizer_pop(a, self);
    if (!style) {
        // Py_DECREF(padding);
        return -1;
    }

    self->head++;
    restore_point = self->topstack->ident;
    // table = Tokenizer_parse(a, self, LC_TABLE_OPEN, 1);
    if (BAD_ROUTE) {
        RESET_ROUTE();
        // Py_DECREF(padding);
        // Py_DECREF(style);
        while (!Tokenizer_IS_CURRENT_STACK(self, restore_point)) {
            Tokenizer_memoize_bad_route(a, self);
            trash = Tokenizer_pop(a, self);
            // Py_XDECREF(trash);
        }
        self->head = reset;
        if (Tokenizer_emit_char(a, self, '{')) {
            return -1;
        }
        return 0;
    }
    if (!table) {
        // Py_DECREF(padding);
        // Py_DECREF(style);
        return -1;
    }

    if (Tokenizer_emit_table_tag(
            self, "{|", "table", style, padding, NULL, table, "|}")) {
        return -1;
    }
    // Offset displacement done by _parse()
    self->head--;
    return 0;
}

/*
    Parse as style until end of the line, then continue.
*/
static int
Tokenizer_handle_table_row(memory_arena_t *a, Tokenizer *self)
{
    void *padding, *style, *row;
    self->head += 2;

    if (!Tokenizer_CAN_RECURSE(self)) {
        if (Tokenizer_emit_text(a, self, "|-")) {
            return -1;
        }
        self->head -= 1;
        return 0;
    }

    if (Tokenizer_check_route(self, LC_TABLE_OPEN | LC_TABLE_ROW_OPEN) < 0) {
        return 0;
    }
    if (Tokenizer_push(a, self, LC_TABLE_OPEN | LC_TABLE_ROW_OPEN)) {
        return -1;
    }
    padding = Tokenizer_handle_table_style(self, '\n');
    if (BAD_ROUTE) {
        return 0;
    }
    if (!padding) {
        return -1;
    }
    style = Tokenizer_pop(a, self);
    if (!style) {
        // Py_DECREF(padding);
        return -1;
    }

    // Don't parse the style separator
    self->head++;
    row = Tokenizer_parse(a, self, LC_TABLE_OPEN | LC_TABLE_ROW_OPEN, 1);
    if (!row) {
        // Py_DECREF(padding);
        // Py_DECREF(style);
        return -1;
    }

    if (Tokenizer_emit_table_tag(self, "|-", "tr", style, padding, NULL, row, "")) {
        return -1;
    }
    // Offset displacement done by _parse()
    self->head--;
    return 0;
}

/*
    Parse as normal syntax unless we hit a style marker, then parse style
    as HTML attributes and the remainder as normal syntax.
*/
static int
Tokenizer_handle_table_cell(Tokenizer *self,
                            const char *markup,
                            const char *tag,
                            uint64_t line_context)
{
    puts("table cell not impl");
    exit(1);
    return -1;

    // uint64_t old_context = self->topstack->context;
    // uint64_t cell_context;
    // Py_ssize_t reset;
    // PyObject *padding, *cell, *style = NULL;
    // const char *close_open_markup = NULL;

    // self->head += strlen(markup);
    // reset = self->head;

    // if (!Tokenizer_CAN_RECURSE(self)) {
    //     if (Tokenizer_emit_text(self, markup)) {
    //         return -1;
    //     }
    //     self->head--;
    //     return 0;
    // }

    // cell = Tokenizer_parse(self,
    //                        LC_TABLE_OPEN | LC_TABLE_CELL_OPEN |
    //                        LC_TABLE_CELL_STYLE |
    //                            line_context,
    //                        1);
    // if (!cell) {
    //     return -1;
    // }
    // cell_context = self->topstack->context;
    // self->topstack->context = old_context;

    // if (cell_context & LC_TABLE_CELL_STYLE) {
    //     Py_DECREF(cell);
    //     self->head = reset;
    //     if (Tokenizer_push(self, LC_TABLE_OPEN | LC_TABLE_CELL_OPEN |
    //     line_context)) {
    //         return -1;
    //     }
    //     padding = Tokenizer_handle_table_style(self, '|');
    //     if (!padding) {
    //         return -1;
    //     }
    //     style = Tokenizer_pop(self);
    //     if (!style) {
    //         Py_DECREF(padding);
    //         return -1;
    //     }
    //     // Don't parse the style separator
    //     self->head++;
    //     cell =
    //         Tokenizer_parse(self, LC_TABLE_OPEN | LC_TABLE_CELL_OPEN |
    //         line_context, 1);
    //     if (!cell) {
    //         Py_DECREF(padding);
    //         Py_DECREF(style);
    //         return -1;
    //     }
    //     cell_context = self->topstack->context;
    //     self->topstack->context = old_context;
    // } else {
    //     padding = PyUnicode_FromString("");
    //     if (!padding) {
    //         Py_DECREF(cell);
    //         return -1;
    //     }
    // }

    // if (style) {
    //     close_open_markup = "|";
    // }
    // if (Tokenizer_emit_table_tag(
    //         self, markup, tag, style, padding, close_open_markup, cell, "")) {
    //     return -1;
    // }
    //// Keep header/cell line contexts
    // self->topstack->context |= cell_context & (LC_TABLE_TH_LINE |
    // LC_TABLE_TD_LINE);
    //// Offset displacement done by parse()
    // self->head--;
    // return 0;
}

/*
    Returns the context, stack, and whether to reset the cell for style
    in a tuple.
*/
static TokenList *
Tokenizer_handle_table_cell_end(memory_arena_t *a, Tokenizer *self, int reset_for_style)
{
    if (reset_for_style) {
        self->topstack->context |= LC_TABLE_CELL_STYLE;
    } else {
        self->topstack->context &= ~LC_TABLE_CELL_STYLE;
    }
    return Tokenizer_pop_keeping_context(a, self);
}

/*
    Return the stack in order to handle the table row end.
*/
static TokenList *
Tokenizer_handle_table_row_end(memory_arena_t *a, Tokenizer *self)
{
    return Tokenizer_pop(a, self);
}

/*
    Return the stack in order to handle the table end.
*/
static TokenList *
Tokenizer_handle_table_end(memory_arena_t *a, Tokenizer *self)
{
    self->head += 2;
    return Tokenizer_pop(a, self);
}

/*
    Handle the end of the stream of wikitext.
*/
static TokenList *
Tokenizer_handle_end(memory_arena_t *a, Tokenizer *self, uint64_t context)
{
    if (context & AGG_FAIL) {
        if (context & LC_TAG_BODY) {
            if (self->topstack->tokenlist->len < 2)
                return NULL;
            Token token = self->topstack->tokenlist->tokens[1];
            puts("LC_TAG_BODY not implemented yet");
            exit(1);
            return NULL;
            // text = PyObject_GetAttrString(token, "text");
            // if (!text) {
            //     return NULL;
            // }
            // single = is_single(text);
            // Py_DECREF(text);
            // if (single) {
            //     return Tokenizer_handle_single_tag_end(self);
            // }
        } else {
            if (context & LC_TABLE_CELL_OPEN) {
                /* trash = */ Tokenizer_pop(a, self);
                context = self->topstack->context;
            }
            if (context & AGG_DOUBLE) {
                /* trash = */ Tokenizer_pop(a, self);
            }
        }
        return Tokenizer_fail_route(a, self);
    }
    return Tokenizer_pop(a, self);
}

/*
    Make sure we are not trying to write an invalid character. Return 0 if
    everything is safe, or -1 if the route must be failed.
*/
static int
Tokenizer_verify_safe(Tokenizer *self, uint64_t context, char data)
{
    if (context & LC_FAIL_NEXT) {
        return -1;
    }
    if (context & LC_WIKILINK_TITLE) {
        if (data == ']' || data == '{') {
            self->topstack->context |= LC_FAIL_NEXT;
        } else if (data == '\n' || data == '[' || data == '}' || data == '>') {
            return -1;
        } else if (data == '<') {
            if (Tokenizer_read(self, 1) == '!') {
                self->topstack->context |= LC_FAIL_NEXT;
            } else {
                return -1;
            }
        }
        return 0;
    }
    if (context & LC_EXT_LINK_TITLE) {
        return (data == '\n') ? -1 : 0;
    }
    if (context & LC_TAG_CLOSE) {
        return (data == '<') ? -1 : 0;
    }
    if (context & LC_TEMPLATE_NAME) {
        if (data == '{') {
            self->topstack->context |= LC_HAS_TEMPLATE | LC_FAIL_NEXT;
            return 0;
        }
        if (data == '}' || (data == '<' && Tokenizer_read(self, 1) == '!')) {
            self->topstack->context |= LC_FAIL_NEXT;
            return 0;
        }
        if (data == '[' || data == ']' || data == '<' || data == '>') {
            return -1;
        }
        if (data == '|') {
            return 0;
        }
        if (context & LC_HAS_TEXT) {
            if (context & LC_FAIL_ON_TEXT) {
                if (!isspace(data)) {
                    return -1;
                }
            } else if (data == '\n') {
                self->topstack->context |= LC_FAIL_ON_TEXT;
            }
        } else if (!isspace(data)) {
            self->topstack->context |= LC_HAS_TEXT;
        }
    } else {
        if (context & LC_FAIL_ON_EQUALS) {
            if (data == '=') {
                return -1;
            }
        } else if (context & LC_FAIL_ON_LBRACE) {
            if (data == '{' || (Tokenizer_read_backwards(self, 1) == '{' &&
                                Tokenizer_read_backwards(self, 2) == '{')) {
                if (context & LC_TEMPLATE) {
                    self->topstack->context |= LC_FAIL_ON_EQUALS;
                } else {
                    self->topstack->context |= LC_FAIL_NEXT;
                }
                return 0;
            }
            self->topstack->context ^= LC_FAIL_ON_LBRACE;
        } else if (context & LC_FAIL_ON_RBRACE) {
            if (data == '}') {
                self->topstack->context |= LC_FAIL_NEXT;
                return 0;
            }
            self->topstack->context ^= LC_FAIL_ON_RBRACE;
        } else if (data == '{') {
            self->topstack->context |= LC_FAIL_ON_LBRACE;
        } else if (data == '}') {
            self->topstack->context |= LC_FAIL_ON_RBRACE;
        }
    }
    return 0;
}

/*
    Returns whether the current head has leading whitespace.
    TODO: treat comments and templates as whitespace, allow fail on non-newline
   spaces.
*/
static int
Tokenizer_has_leading_whitespace(Tokenizer *self)
{
    int offset = 1;
    char current_character;
    while (1) {
        current_character = Tokenizer_read_backwards(self, offset);
        if (!current_character || current_character == '\n') {
            return 1;
        } else if (!isspace(current_character)) {
            return 0;
        }
        offset++;
    }
}

/*
    Parse the wikicode string, using context for when to stop. If push is true,
    we will push a new context, otherwise we won't and context will be ignored.
*/
TokenList *
Tokenizer_parse(memory_arena_t *a, Tokenizer *self, uint64_t context, int push)
{
    assert(a->capacity > 0);
    uint64_t this_context;
    char this, next, next_next, last;
    void *temp;

    if (push) {
        if (Tokenizer_check_route(self, context) < 0) {
            return NULL;
        }
        if (Tokenizer_push(a, self, context)) {
            return NULL;
        }
    }
    while (1) {
        this = Tokenizer_read(self, 0);
        this_context = self->topstack->context;
        if (this_context & AGG_UNSAFE) {
            if (Tokenizer_verify_safe(self, this_context, this) < 0) {
                if (this_context & AGG_DOUBLE) {
                    temp = Tokenizer_pop(a, self);
                }
                return Tokenizer_fail_route(a, self);
            }
        }
        if (!is_marker(this)) {
            if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
            self->head++;
            continue;
        }
        if (!this) {
            return Tokenizer_handle_end(a, self, this_context);
        }
        next = Tokenizer_read(self, 1);
        last = Tokenizer_read_backwards(self, 1);
        if (this == next && next == '{') {
            if (Tokenizer_CAN_RECURSE(self)) {
                if (Tokenizer_parse_template_or_argument(a, self)) {
                    return NULL;
                }
            } else if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else if (this == '|' && this_context & LC_TEMPLATE) {
            if (Tokenizer_handle_template_param(a, self)) {
                return NULL;
            }
        } else if (this == '=' && this_context & LC_TEMPLATE_PARAM_KEY) {
            if (!(self->global & GL_HEADING) && (!last || last == '\n') &&
                next == '=') {
                if (Tokenizer_parse_heading(a, self)) {
                    return NULL;
                }
            } else if (Tokenizer_handle_template_param_value(a, self)) {
                return NULL;
            }
        } else if (this == next && next == '}' && this_context & LC_TEMPLATE) {
            return Tokenizer_handle_template_end(a, self);
        } else if (this == '|' && this_context & LC_ARGUMENT_NAME) {
            if (Tokenizer_handle_argument_separator(a, self)) {
                return NULL;
            }
        } else if (this == next && next == '}' && this_context & LC_ARGUMENT) {
            if (Tokenizer_read(self, 2) == '}') {
                return Tokenizer_handle_argument_end(a, self);
            }
            if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else if (this == next && next == '[' && Tokenizer_CAN_RECURSE(self)) {
            // TODO: Only do this if not in a file context:
            // if (this_context & LC_WIKILINK_TEXT) {
            //     return Tokenizer_fail_route(self);
            // }
            if (!(this_context & AGG_NO_WIKILINKS)) {
                if (Tokenizer_parse_wikilink(a, self)) {
                    return NULL;
                }
            } else if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else if (this == '|' && this_context & LC_WIKILINK_TITLE) {
            if (Tokenizer_handle_wikilink_separator(a, self)) {
                return NULL;
            }
        } else if (this == next && next == ']' && this_context & LC_WIKILINK) {
            return Tokenizer_handle_wikilink_end(a, self);
        } else if (this == '[') {
            if (Tokenizer_parse_external_link(a, self, 1)) {
                return NULL;
            }
        } else if (this == ':' && !is_marker(last)) {
            if (Tokenizer_parse_external_link(a, self, 0)) {
                return NULL;
            }
        } else if (this == ']' && this_context & LC_EXT_LINK_TITLE) {
            return Tokenizer_pop(a, self);
        } else if (this == '=' && !(self->global & GL_HEADING) &&
                   !(this_context & LC_TEMPLATE)) {
            if (!last || last == '\n') {
                if (Tokenizer_parse_heading(a, self)) {
                    return NULL;
                }
            } else if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else if (this == '=' && this_context & LC_HEADING) {
            return (void *) Tokenizer_handle_heading_end(a, self);
        } else if (this == '\n' && this_context & LC_HEADING) {
            return Tokenizer_fail_route(a, self);
        } else if (this == '&') {
            if (Tokenizer_parse_entity(a, self)) {
                return NULL;
            }
        } else if (this == '<' && next == '!') {
            next_next = Tokenizer_read(self, 2);
            if (next_next == Tokenizer_read(self, 3) && next_next == '-') {
                if (Tokenizer_parse_comment(a, self)) {
                    return NULL;
                }
            } else if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else if (this == '<' && next == '/' && Tokenizer_read(self, 2)) {
            if (this_context & LC_TAG_BODY
                    ? Tokenizer_handle_tag_open_close(a, self)
                    : Tokenizer_handle_invalid_tag_start(a, self)) {
                return NULL;
            }
        } else if (this == '<' && !(this_context & LC_TAG_CLOSE)) {
            if (Tokenizer_CAN_RECURSE(self)) {
                if (Tokenizer_parse_tag(a, self)) {
                    return NULL;
                }
            } else if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else if (this == '>' && this_context & LC_TAG_CLOSE) {
            return Tokenizer_handle_tag_close_close(self);
        } else if (this == next && next == '\'' && !self->skip_style_tags) {
            TokenList *intermediate = Tokenizer_parse_style(a, self);
            if (intermediate)
                return intermediate;
            // Otherwise, text was emitted in `Tokenizer_parse_style`
        } else if ((!last || last == '\n') &&
                   (this == '#' || this == '*' || this == ';' || this == ':')) {
            if (Tokenizer_handle_list(a, self)) {
                return NULL;
            }
        } else if ((!last || last == '\n') &&
                   (this == '-' && this == next && this == Tokenizer_read(self, 2) &&
                    this == Tokenizer_read(self, 3))) {
            if (Tokenizer_handle_hr(a, self)) {
                return NULL;
            }
        } else if ((this == '\n' || this == ':') && this_context & LC_DLTERM) {
            if (Tokenizer_handle_dl_term(a, self)) {
                return NULL;
            }
            // Kill potential table contexts
            if (this == '\n') {
                self->topstack->context &= ~LC_TABLE_CELL_LINE_CONTEXTS;
            }
        }

        // Start of table parsing
        else if (this == '{' && next == '|' && Tokenizer_has_leading_whitespace(self)) {
            if (Tokenizer_CAN_RECURSE(self)) {
                if (Tokenizer_parse_table(a, self)) {
                    return NULL;
                }
            } else if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
        } else if (this_context & LC_TABLE_OPEN) {
            if (this == '|' && next == '|' && this_context & LC_TABLE_TD_LINE) {
                if (this_context & LC_TABLE_CELL_OPEN) {
                    return Tokenizer_handle_table_cell_end(a, self, 0);
                } else if (Tokenizer_handle_table_cell(
                               self, "||", "td", LC_TABLE_TD_LINE)) {
                    return NULL;
                }
            } else if (this == '|' && next == '|' && this_context & LC_TABLE_TH_LINE) {
                if (this_context & LC_TABLE_CELL_OPEN) {
                    return Tokenizer_handle_table_cell_end(a, self, 0);
                } else if (Tokenizer_handle_table_cell(
                               self, "||", "th", LC_TABLE_TH_LINE)) {
                    return NULL;
                }
            } else if (this == '!' && next == '!' && this_context & LC_TABLE_TH_LINE) {
                if (this_context & LC_TABLE_CELL_OPEN) {
                    return Tokenizer_handle_table_cell_end(a, self, 0);
                } else if (Tokenizer_handle_table_cell(
                               self, "!!", "th", LC_TABLE_TH_LINE)) {
                    return NULL;
                }
            } else if (this == '|' && this_context & LC_TABLE_CELL_STYLE) {
                return Tokenizer_handle_table_cell_end(a, self, 1);
            }
            // On newline, clear out cell line contexts
            else if (this == '\n' && this_context & LC_TABLE_CELL_LINE_CONTEXTS) {
                self->topstack->context &= ~LC_TABLE_CELL_LINE_CONTEXTS;
                if (Tokenizer_emit_char(a, self, this)) {
                    return NULL;
                }
            } else if (Tokenizer_has_leading_whitespace(self)) {
                if (this == '|' && next == '}') {
                    if (this_context & LC_TABLE_CELL_OPEN) {
                        return Tokenizer_handle_table_cell_end(a, self, 0);
                    }
                    if (this_context & LC_TABLE_ROW_OPEN) {
                        return Tokenizer_handle_table_row_end(a, self);
                    } else {
                        return Tokenizer_handle_table_end(a, self);
                    }
                } else if (this == '|' && next == '-') {
                    if (this_context & LC_TABLE_CELL_OPEN) {
                        return Tokenizer_handle_table_cell_end(a, self, 0);
                    }
                    if (this_context & LC_TABLE_ROW_OPEN) {
                        return Tokenizer_handle_table_row_end(a, self);
                    } else if (Tokenizer_handle_table_row(a, self)) {
                        return NULL;
                    }
                } else if (this == '|') {
                    if (this_context & LC_TABLE_CELL_OPEN) {
                        return Tokenizer_handle_table_cell_end(a, self, 0);
                    } else if (Tokenizer_handle_table_cell(
                                   self, "|", "td", LC_TABLE_TD_LINE)) {
                        return NULL;
                    }
                } else if (this == '!') {
                    if (this_context & LC_TABLE_CELL_OPEN) {
                        return Tokenizer_handle_table_cell_end(a, self, 0);
                    } else if (Tokenizer_handle_table_cell(
                                   self, "!", "th", LC_TABLE_TH_LINE)) {
                        return NULL;
                    }
                } else if (Tokenizer_emit_char(a, self, this)) {
                    return NULL;
                }
            } else if (Tokenizer_emit_char(a, self, this)) {
                return NULL;
            }
            // Raise BadRoute to table start
            if (BAD_ROUTE) {
                return NULL;
            }
        } else if (Tokenizer_emit_char(a, self, this)) {
            return NULL;
        }
        self->head++;
    }
}
