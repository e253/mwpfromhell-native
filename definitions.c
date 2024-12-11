/*
Copyright (C) 2012-2020 Ben Kurtovic <ben.kurtovic@gmail.com>

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

#include "definitions.h"

/*
    This file should be kept up to date with mwparserfromhell/definitions.py.
    See the Python version for data sources.
*/

// clang-format off
static const char *URI_SCHEMES[] = {
    "bitcoin",
    "ftp",
    "ftps",
    "geo",
    "git",
    "gopher",
    "http",
    "https",
    "irc",
    "ircs",
    "magnet",
    "mailto",
    "mms",
    "news",
    "nntp",
    "redis",
    "sftp",
    "sip",
    "sips",
    "sms",
    "ssh",
    "svn",
    "tel",
    "telnet",
    "urn",
    "worldwind",
    "xmpp",
    NULL,
};

static const char *URI_SCHEMES_AUTHORITY_OPTIONAL[] = {
    "bitcoin",
    "geo",
    "magnet",
    "mailto",
    "news",
    "sip",
    "sips",
    "sms",
    "tel",
    "urn",
    "xmpp",
    NULL,
};

static const char *PARSER_BLACKLIST[] = {
    "categorytree",
    "ce",
    "chem",
    "gallery",
    "graph",
    "hiero",
    "imagemap",
    "inputbox",
    "math",
    "nowiki",
    "pre",
    "score",
    "section",
    "source",
    "syntaxhighlight",
    "templatedata",
    "timeline",
    NULL,
};
// clang-format on

static const char *SINGLE[] = {
    "br", "wbr", "hr", "meta", "link", "img", "li", "dt", "dd", "th", "td", "tr", NULL};

static const char *SINGLE_ONLY[] = {"br", "wbr", "hr", "meta", "link", "img", NULL};

/*
    Return whether a PyUnicodeObject is in a list of lowercase ASCII strings.
*/
static inline int
string_in_string_list(char *input, size_t input_len, const char **list)
{
    int i = 0;
    const char* target = list[i];
    while (target != NULL) {
        if (strncmp(target, input, input_len) == 0)
            return 1;

        i++;
        target = list[i];
    }

    return 0;
}

/*
    Return if the given tag's contents should be passed to the parser.
*/
int
is_parsable(char *tag, size_t tag_len)
{
    return !string_in_string_list(tag, tag_len, PARSER_BLACKLIST);
}

/*
    Return whether or not the given tag can exist without a close tag.
*/
int
is_single(char *tag, size_t tag_len)
{
    return string_in_string_list(tag, tag_len, SINGLE);
}

/*
    Return whether or not the given tag must exist without a close tag.
*/
int
is_single_only(char *tag, size_t tag_len)
{
    return string_in_string_list(tag, tag_len, SINGLE_ONLY);
}

/*
    Return whether the given scheme is valid for external links.
*/
int
is_scheme(char *scheme, size_t scheme_len, int slashes)
{
    if (slashes) {
        return string_in_string_list(scheme, scheme_len, URI_SCHEMES);
    } else {
        return string_in_string_list(scheme, scheme_len, URI_SCHEMES_AUTHORITY_OPTIONAL);
    }
}
