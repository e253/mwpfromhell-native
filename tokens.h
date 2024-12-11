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

#pragma once

#include <stdbool.h>

typedef enum {
    Text,

    TemplateOpen,
    TemplateParamSeparator,
    TemplateParamEquals,
    TemplateClose,

    ArgumentOpen,
    ArgumentSeparator,
    ArgumentClose,

    WikilinkOpen,
    WikilinkSeparator,
    WikilinkClose,

    ExternalLinkOpen,
    ExternalLinkSeparator,
    ExternalLinkClose,

    HTMLEntityStart,
    HTMLEntityNumeric,
    HTMLEntityHex,
    HTMLEntityEnd,
    HeadingStart,
    HeadingEnd,

    CommentStart,
    CommentEnd,

    TagOpenOpen,
    TagAttrStart,
    TagAttrEquals,
    TagAttrQuote,
    TagCloseOpen,
    TagCloseSelfclose,
    TagOpenClose,
    TagCloseClose,
} TokenType;

inline const char* TokenTypeString(TokenType tt)
{
#define Case_Return(enum) \
    case enum:            \
        return #enum;

    switch (tt) {
        Case_Return(Text);
        Case_Return(TemplateOpen);
        Case_Return(TemplateParamSeparator);
        Case_Return(TemplateParamEquals);
        Case_Return(TemplateClose);
        Case_Return(ArgumentOpen);
        Case_Return(ArgumentSeparator);
        Case_Return(ArgumentClose);
        Case_Return(WikilinkOpen);
        Case_Return(WikilinkSeparator);
        Case_Return(WikilinkClose);
        Case_Return(ExternalLinkOpen);
        Case_Return(ExternalLinkSeparator);
        Case_Return(ExternalLinkClose);
        Case_Return(HTMLEntityStart);
        Case_Return(HTMLEntityNumeric);
        Case_Return(HTMLEntityHex);
        Case_Return(HTMLEntityEnd);
        Case_Return(HeadingStart);
        Case_Return(HeadingEnd);
        Case_Return(CommentStart);
        Case_Return(CommentEnd);
        Case_Return(TagOpenOpen);
        Case_Return(TagAttrStart);
        Case_Return(TagAttrEquals);
        Case_Return(TagAttrQuote);
        Case_Return(TagCloseOpen);
        Case_Return(TagCloseSelfclose);
        Case_Return(TagOpenClose);
        Case_Return(TagCloseClose);
    }
}

typedef struct {
    bool space;
} ExternalLinkSeparatorContext;

typedef struct {
    bool brackets;
} ExternalLinkOpenContext;

typedef struct {
    char level;
} HeadingContext;

typedef struct {
    TokenType type;

    union {
        ExternalLinkSeparatorContext external_link_sep;
        ExternalLinkOpenContext external_link_open;
        HeadingContext heading;
        void* data; // default
    } ctx;
} Token;

#define TOKEN(variable_name, type_value) \
    Token variable_name;                 \
    variable_name.type = type_value;     \
    variable_name.ctx.data = NULL;

#define TOKEN_CTX(variable_name, type_value) \
    Token variable_name;                     \
    variable_name.type = type_value;
