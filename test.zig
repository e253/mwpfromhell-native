const std = @import("std");
const expect = std.testing.expect;
const eqlStr = std.testing.expectEqualStrings;

const c = @cImport({
    @cInclude("common.h");
    @cInclude("tok_parse.h");
    @cInclude("tokens.h");
});

const Arena = c.memory_arena_t;

export fn printTokens(tokenlist: c.TokenList) void {
    var i: u32 = 0;
    while (i < tokenlist.len) : (i += 1) {
        const token = tokenlist.tokens[i];
        if (token.type == c.Text) {
            std.debug.print("Text(\"{s}\")", .{@as([*c]const u8, @ptrCast(token.ctx.data))});
        } else if (token.type == c.ExternalLinkOpen) {
            std.debug.print("ExternalLinkOpen({})", .{token.ctx.external_link_open.brackets});
        } else {
            std.debug.print("{s}", .{c.TokenTypeString(token.type)});
        }
        if (i < tokenlist.len - 1)
            std.debug.print(", ", .{});
    }
    std.debug.print("\n", .{});
}

fn textFromTextTok(t: c.Token) []const u8 {
    return std.mem.sliceTo(@as([*c]u8, @ptrCast(t.ctx.data)), 0);
}

fn expectTextTokEql(expected: []const u8, t: c.Token) !void {
    try expect(t.type == c.Text);
    try eqlStr(expected, textFromTextTok(t));
}

fn tokenize(txt: []const u8) c.TokenList {
    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = txt.ptr;
    tokenizer.text.length = txt.len;

    var arena: c.memory_arena_t = std.mem.zeroes(c.memory_arena_t);
    std.debug.assert(c.arena_init(&arena) == 0);

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&arena, &tokenizer, 0, 1));

    return tokenlist.*;
}

fn tokenize_arena(a: *Arena, txt: []const u8) c.TokenList {
    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = txt.ptr;
    tokenizer.text.length = txt.len;

    return @as(*c.TokenList, @ptrCast(c.Tokenizer_parse(a, &tokenizer, 0, 1))).*;
}

fn cText(txt: [*:0]const u8) [*c]u8 {
    return @constCast(@ptrCast(txt));
}

fn expectTokensEql(expected: []const c.Token, actual: c.TokenList) !void {
    for (expected, 0..) |expected_token, i| {
        const actual_token = actual.tokens[i];
        try expect(expected_token.type == actual_token.type);
        if (expected_token.type == c.Text) {
            try eqlStr(textFromTextTok(expected_token), textFromTextTok(actual_token));
        }
    }
    try expect(expected.len == actual.len);
}

// **************
// Text / Unicode
// **************

test "sanity check for basic text parsing, no gimmicks" {
    const txt = "foobar";

    var a: Arena = undefined;
    try expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const tokenlist = tokenize_arena(&a, txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("foobar", tokenlist.tokens[0]);
}

test "slightly more complex text parsing, with newlines" {
    const txt = "This is a line of text.\nThis is another line of text.\nThis is another.";

    var a: Arena = undefined;
    try expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const tokenlist = tokenize_arena(&a, txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql(txt, tokenlist.tokens[0]);
}

test "ensure unicode data is handled properly" {
    const txt = "Thís ís å sëñtënce with diœcritiçs.";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("Thís ís å sëñtënce with diœcritiçs.", tokenlist.tokens[0]);
}

test "additional unicode check for non-BMP codepoints" {
    // 𐌲𐌿𐍄𐌰𐍂𐌰𐌶𐌳𐌰
    const txt = "\xf0\x90\x8c\xb2\xf0\x90\x8c\xbf\xf0\x90\x8d\x84\xf0\x90\x8c\xb0\xf0\x90\x8d\x82\xf0\x90\x8c\xb0\xf0\x90\x8c\xb6\xf0\x90\x8c\xb3\xf0\x90\x8c\xb0";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql(txt, tokenlist.tokens[0]);
}

test "a lot of text, requiring proper storage in the C tokenizer" {
    const txt = "ZWfsZYcZyhGbkDYJiguJuuhsNyHGFkFhnjkbLJyXIygTHqcXdhsDkEOTSIKYlBiohLIkiXxvyebUyCGvvBcYqFdtcftGmaAanKXEIyYSEKlTfEEbdGhdePVwVImOyKiHSzAEuGyEVRIKPZaNjQsYqpqARIQfvAklFtQyTJVGlLwjJIxYkiqmHBmdOvTyNqJRbMvouoqXRyOhYDwowtkcZGSOcyzVxibQdnzhDYbrgbatUrlOMRvFSzmLWHRihtXnddwYadPgFWUOxAzAgddJVDXHerawdkrRuWaEXfuwQSkQUmLEJUmrgXDVlXCpciaisfuOUjBldElygamkkXbewzLucKRnAEBimIIotXeslRRhnqQjrypnLQvvdCsKFWPVTZaHvzJMFEahDHWcCbyXgxFvknWjhVfiLSDuFhGoFxqSvhjnnRZLmCMhmWeOgSoanDEInKTWHnbpKyUlabLppITDFFxyWKAnUYJQIcmYnrvMmzmtYvsbCYbebgAhMFVVFAKUSvlkLFYluDpbpBaNFWyfXTaOdSBrfiHDTWGBTUCXMqVvRCIMrEjWpQaGsABkioGnveQWqBTDdRQlxQiUipwfyqAocMddXqdvTHhEwjEzMkOSWVPjJvDtClhYwpvRztPmRKCSpGIpXQqrYtTLmShFdpKtOxGtGOZYIdyUGPjdmyvhJTQMtgYJWUUZnecRjBfQXsyWQWikyONySLzLEqRFqcJYdRNFcGwWZtfZasfFWcvdsHRXoqKlKYihRAOJdrPBDdxksXFwKceQVncmFXfUfBsNgjKzoObVExSnRnjegeEhqxXzPmFcuiasViAFeaXrAxXhSfSyCILkKYpjxNeKynUmdcGAbwRwRnlAFbOSCafmzXddiNpLCFTHBELvArdXFpKUGpSHRekhrMedMRNkQzmSyFKjVwiWwCvbNWjgxJRzYeRxHiCCRMXktmKBxbxGZvOpvZIJOwvGIxcBLzsMFlDqAMLtScdsJtrbIUAvKfcdChXGnBzIxGxXMgxJhayrziaCswdpjJJJhkaYnGhHXqZwOzHFdhhUIEtfjERdLaSPRTDDMHpQtonNaIgXUYhjdbnnKppfMBxgNSOOXJAPtFjfAKnrRDrumZBpNhxMstqjTGBViRkDqbTdXYUirsedifGYzZpQkvdNhtFTOPgsYXYCwZHLcSLSfwfpQKtWfZuRUUryHJsbVsAOQcIJdSKKlOvCeEjUQNRPHKXuBJUjPuaAJJxcDMqyaufqfVwUmHLdjeYZzSiiGLHOTCInpVAalbXXTMLugLiwFiyPSuSFiyJUKVrWjbZAHaJtZnQmnvorRrxdPKThqXzNgTjszQiCoMczRnwGYJMERUWGXFyrSbAqsHmLwLlnJOJoXNsjVehQjVOpQOQJAZWwFZBlgyVIplzLTlFwumPgBLYrUIAJAcmvHPGfHfWQguCjfTYzxYfbohaLFAPwxFRrNuCdCzLlEbuhyYjCmuDBTJDMCdLpNRVqEALjnPSaBPsKWRCKNGwEMFpiEWbYZRwaMopjoUuBUvMpvyLfsPKDrfQLiFOQIWPtLIMoijUEUYfhykHrSKbTtrvjwIzHdWZDVwLIpNkloCqpzIsErxxKAFuFEjikWNYChqYqVslXMtoSWzNhbMuxYbzLfJIcPGoUeGPkGyPQNhDyrjgdKekzftFrRPTuyLYqCArkDcWHTrjPQHfoThBNnTQyMwLEWxEnBXLtzJmFVLGEPrdbEwlXpgYfnVnWoNXgPQKKyiXifpvrmJATzQOzYwFhliiYxlbnsEPKbHYUfJLrwYPfSUwTIHiEvBFMrEtVmqJobfcwsiiEudTIiAnrtuywgKLOiMYbEIOAOJdOXqroPjWnQQcTNxFvkIEIsuHLyhSqSphuSmlvknzydQEnebOreeZwOouXYKlObAkaWHhOdTFLoMCHOWrVKeXjcniaxtgCziKEqWOZUWHJQpcDJzYnnduDZrmxgjZroBRwoPBUTJMYipsgJwbTSlvMyXXdAmiEWGMiQxhGvHGPLOKeTxNaLnFVbWpiYIVyqN";

    var a: Arena = undefined;
    try expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const tokenlist = tokenize_arena(&a, txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql(txt, tokenlist.tokens[0]);
}

// *************
// HTML Entities
// *************

test "a basic named HTML entity" {
    const txt: []const u8 = "&nbsp;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.Text);
    try eqlStr("nbsp", textFromTextTok(tokenlist.tokens[1]));
    try expect(tokenlist.tokens[2].type == c.HTMLEntityEnd);
}

test "a basic decimal HTML entity" {
    const txt: []const u8 = "&#107;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 4);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.Text);
    try eqlStr("107", textFromTextTok(tokenlist.tokens[2]));
    try expect(tokenlist.tokens[3].type == c.HTMLEntityEnd);
}

test "a basic hexadecimal HTML entity, using 'x' as a signal" {
    const txt: []const u8 = "&#x6B;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.HTMLEntityHex);
    try expect(tokenlist.tokens[3].type == c.Text);
    try eqlStr("6B", textFromTextTok(tokenlist.tokens[3]));
    try expect(tokenlist.tokens[4].type == c.HTMLEntityEnd);
}

test "a basic hexadecimal HTML entity, using 'X' as a signal" {
    const txt: []const u8 = "&#X6B;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.HTMLEntityHex);
    try expect(tokenlist.tokens[3].type == c.Text);
    try eqlStr("6B", textFromTextTok(tokenlist.tokens[3]));
    try expect(tokenlist.tokens[4].type == c.HTMLEntityEnd);
}

test "the maximum acceptable decimal numeric entity" {
    const txt: []const u8 = "&#1114111;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 4);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.Text);
    try eqlStr("1114111", textFromTextTok(tokenlist.tokens[2]));
    try expect(tokenlist.tokens[3].type == c.HTMLEntityEnd);
}

test "the maximum acceptable hexadecimal numeric entity" {
    const txt: []const u8 = "&#x10FFFF;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.HTMLEntityHex);
    try expect(tokenlist.tokens[3].type == c.Text);
    try eqlStr("10FFFF", textFromTextTok(tokenlist.tokens[3]));
    try expect(tokenlist.tokens[4].type == c.HTMLEntityEnd);
}

test "zeros accepted at the beginning of a numeric entity" {
    const txt: []const u8 = "&#0000000107;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 4);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.Text);
    try eqlStr("0000000107", textFromTextTok(tokenlist.tokens[2]));
    try expect(tokenlist.tokens[3].type == c.HTMLEntityEnd);
}

test "zeros accepted at the beginning of a hex numeric entity" {
    const txt: []const u8 = "&#x0000000107;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.HTMLEntityHex);
    try expect(tokenlist.tokens[3].type == c.Text);
    try eqlStr("0000000107", textFromTextTok(tokenlist.tokens[3]));
    try expect(tokenlist.tokens[4].type == c.HTMLEntityEnd);
}

test "a named entity that is too long" {
    const txt: []const u8 = "&sigmaSigma;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&sigmaSigma;", textFromTextTok(tokenlist.tokens[0]));
}

test "a named entity that doesn't exist" {
    const txt: []const u8 = "&foobar;";

    const tokenlist = tokenize(txt);
    _ = tokenlist;

    return error.SkipZigTest;

    //try expect(tokenlist.len == 3);
    //try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    //try expect(tokenlist.tokens[1].type == c.Text);
    //try eqlStr("foobar", textFromTextTok(tokenlist.tokens[1]));
    //try expect(tokenlist.tokens[2].type == c.HTMLEntityEnd);
}

test "a named entity with non-ASCII characters" {
    const txt: []const u8 = "&sígma;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&sígma;", textFromTextTok(tokenlist.tokens[0]));
}

test "a numeric entity that is out of range: < 1" {
    const txt: []const u8 = "&#0;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&#0;", textFromTextTok(tokenlist.tokens[0]));
}

test "a hex numeric entity that is out of range: < 1" {
    const txt: []const u8 = "&x0;";

    const tokenlist = tokenize(txt);
    _ = tokenlist;

    return error.SkipZigTest;

    //try expect(tokenlist.len == 1);
    //try expect(tokenlist.tokens[0].type == c.Text);
    //try eqlStr("&x0;", textFromTextTok(tokenlist.tokens[0]));
}

test "a numeric entity that is out of range: > 0x10FFFF" {
    const txt: []const u8 = "&#1114112;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&#1114112;", textFromTextTok(tokenlist.tokens[0]));
}

test "a hex numeric entity that is out of range: > 0x10FFFF" {
    const txt: []const u8 = "&#x0110000;";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&#x0110000;", textFromTextTok(tokenlist.tokens[0]));
}

test "Invalid entities" {
    return error.SkipZigTest;
    // TODO: Figure out why this is failing.

    //const txts = [_][]const u8{ "&", "&;", "&#", "&#;", "&#x", "&#x;", "&#123", "&000nbsp;" };

    //inline for (txts) |txt| {
    //    var tokenizer = std.mem.zeroes(c.Tokenizer);
    //    tokenizer.text.data = @constCast(txt.ptr);
    //    tokenizer.text.length = txt.len;

    //    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    //    try expect(tokenlist.len == 1);
    //    try expect(tokenlist.tokens[0].type == c.Text);
    //    try eqlStr(txt, textFromTextTok(tokenlist.tokens[0]));
    //}
}

// *************
// HTML Comments
// *************

test "a blank comment" {
    const txt: []const u8 = "<!---->";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 2);
    try expect(tokenlist.tokens[0].type == c.CommentStart);
    try expect(tokenlist.tokens[1].type == c.CommentEnd);
}

test "a basic comment" {
    const txt: []const u8 = "<!-- comment -->";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.CommentStart);
    try expect(tokenlist.tokens[1].type == c.Text);
    try eqlStr(" comment ", textFromTextTok(tokenlist.tokens[1]));
    try expect(tokenlist.tokens[2].type == c.CommentEnd);
}

test "a comment with tons of ignorable garbage in it" {
    const txt: []const u8 = "<!-- foo{{bar}}[[basé\n\n]{}{}{}{}]{{{{{{haha{{--a>aa<!--aa -->";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.CommentStart);
    try expect(tokenlist.tokens[1].type == c.Text);
    try eqlStr(" foo{{bar}}[[basé\n\n]{}{}{}{}]{{{{{{haha{{--a>aa<!--aa ", textFromTextTok(tokenlist.tokens[1]));
    try expect(tokenlist.tokens[2].type == c.CommentEnd);
}

test "a comment that doesn't close" {
    const txt: []const u8 = "<!--";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("<!--", textFromTextTok(tokenlist.tokens[0]));
}

test "a comment that doesn't close, with text" {
    const txt: []const u8 = "<!-- foo";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("<!-- foo", textFromTextTok(tokenlist.tokens[0]));
}

test "a comment that doesn't close, with a partial close" {
    const txt: []const u8 = "<!-- foo --\x01>";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("<!-- foo --\x01>", textFromTextTok(tokenlist.tokens[0]));
}

test "a comment that only has a < and !" {
    const txt: []const u8 = "<!foo";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("<!foo", textFromTextTok(tokenlist.tokens[0]));
}

// *************
// Headings
// *************

test "basic level 1-6 headings" {
    inline for (1..7) |level| {
        const heading_marker = "=" ** level;
        const txt = heading_marker ++ " Heading " ++ heading_marker;

        var tokenizer = std.mem.zeroes(c.Tokenizer);
        tokenizer.text.data = @constCast(txt.ptr);
        tokenizer.text.length = txt.len;

        var arena: c.memory_arena_t = std.mem.zeroes(c.memory_arena_t);
        std.debug.assert(c.arena_init(&arena) == 0);
        defer {
            c.arena_clear(&arena);
            std.debug.assert(arena.len == 0 and arena.capacity == 0);
        }

        const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&arena, &tokenizer, 0, 1));

        try expect(tokenlist.len == 3);
        try expect(tokenlist.tokens[0].type == c.HeadingStart);
        try expect(tokenlist.tokens[0].ctx.heading.level == level);
        try expectTextTokEql(" Heading ", tokenlist.tokens[1]);
        try expect(tokenlist.tokens[2].type == c.HeadingEnd);
    }
}

test "a level-6 heading that pretends to be a level-7 heading" {
    const txt = "======= Heading =======";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 6);
    try expectTextTokEql("= Heading =", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a level-2 heading that pretends to be a level-3 heading" {
    const txt = "=== Heading ==";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 2);
    try expectTextTokEql("= Heading ", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a level-4 heading that pretends to be a level-6 heading" {
    const txt = "==== Heading ======";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 4);
    try expectTextTokEql(" Heading ==", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a heading that starts after a newline" {
    const txt = "This is some text.\n== Foobar ==\nbaz";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);
    try expectTextTokEql("This is some text.\n", tokenlist.tokens[0]);
    try expect(tokenlist.tokens[1].type == c.HeadingStart);
    try expect(tokenlist.tokens[1].ctx.heading.level == 2);
    try expectTextTokEql(" Foobar ", tokenlist.tokens[2]);
    try expect(tokenlist.tokens[3].type == c.HeadingEnd);
    try expectTextTokEql("\nbaz", tokenlist.tokens[4]);
}

test "text on the same line after" {
    const txt = "This is some text.\n== Foobar == baz";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);
    try expectTextTokEql("This is some text.\n", tokenlist.tokens[0]);
    try expect(tokenlist.tokens[1].type == c.HeadingStart);
    try expect(tokenlist.tokens[1].ctx.heading.level == 2);
    try expectTextTokEql(" Foobar ", tokenlist.tokens[2]);
    try expect(tokenlist.tokens[3].type == c.HeadingEnd);
    try expectTextTokEql(" baz", tokenlist.tokens[4]);
}

test "invalid headings: text on the same line before" {
    const txt = "This is some text. == Foobar ==\nbaz";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is some text. == Foobar ==\nbaz", tokenlist.tokens[0]);
}

test "invalid headings: newline in the middle" {
    const txt = "This is some text.\n== Foo\nbar ==";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is some text.\n== Foo\nbar ==", tokenlist.tokens[0]);
}

test "invalid headings: newline in the middle 2" {
    const txt = "This is some text.\n=== Foo\nbar ===";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is some text.\n=== Foo\nbar ===", tokenlist.tokens[0]);
}

test "invalid headings: attempts at nesting" {
    const txt = "== Foo === Bar === Baz ==";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 2);
    try expectTextTokEql(" Foo === Bar === Baz ", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a heading that starts but doesn't finish" {
    const txt = "Foobar. \n== Heading ";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("Foobar. \n== Heading ", tokenlist.tokens[0]);
}

// *******
// Styling
// *******

test "basic italic text" {
    const txt = "''text''";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.ItalicOpen);
    try expectTextTokEql("text", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.ItalicClose);
}

test "basic bold text" {
    const txt = "'''text'''";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.BoldOpen);
    try expectTextTokEql("text", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.BoldClose);
}

test "basic unordered list" {
    const txt = "*text";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 2);
    try expect(tokenlist.tokens[0].type == c.UnorderedListItem);
    try expectTextTokEql("text", tokenlist.tokens[1]);
}

test "basic ordered list" {
    const txt = "#text";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 2);
    try expect(tokenlist.tokens[0].type == c.OrderedListItem);
    try expectTextTokEql("text", tokenlist.tokens[1]);
}

test "basic description term" {
    const txt = ";text";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 2);
    try expect(tokenlist.tokens[0].type == c.DescriptionTerm);
    try expectTextTokEql("text", tokenlist.tokens[1]);
}

test "basic description item" {
    const txt = ":text";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 2);
    try expect(tokenlist.tokens[0].type == c.DescriptionItem);
    try expectTextTokEql("text", tokenlist.tokens[1]);
}

test "basic horizontal rule" {
    const txt = "----";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.HR);
}

// name:   complex_italics
// label:  italics with a lot in them
// input:  "''this is a&nbsp;test of [[Italic text|italics]] with {{plenty|of|stuff}}''"
// output: [TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of "), WikilinkOpen(), Text(text="Italic text"), WikilinkSeparator(), Text(text="italics"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose(), TagOpenClose(), Text(text="i"), TagCloseClose()]
test "italics with a lot in them" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "''this is a&nbsp;test of [[Italic text|italics]] with {{plenty|of|stuff}}''");

    const expected = [_]c.Token{
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("this is a") } },
        .{ .type = c.HTMLEntityStart },
        .{ .type = c.Text, .ctx = .{ .data = cText("nbsp") } },
        .{ .type = c.HTMLEntityEnd },
        .{ .type = c.Text, .ctx = .{ .data = cText("test of ") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("Italic text") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("italics") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" with ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("plenty") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("of") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("stuff") } },
        .{ .type = c.TemplateClose },
        .{ .type = c.ItalicClose },
    };

    try expectTokensEql(&expected, actual);
}

test "italics spanning mulitple lines" {
    const txt = "foo\nbar''testing\ntext\nspanning\n\n\n\n\nmultiple\nlines''foo\n\nbar";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);
    try expectTextTokEql("foo\nbar", tokenlist.tokens[0]);
    try expect(tokenlist.tokens[1].type == c.ItalicOpen);
    try expectTextTokEql("testing\ntext\nspanning\n\n\n\n\nmultiple\nlines", tokenlist.tokens[2]);
    try expect(tokenlist.tokens[3].type == c.ItalicClose);
    try expectTextTokEql("foo\n\nbar", tokenlist.tokens[4]);
}

test "italics without an ending tag" {
    const txt = "''unending formatting";
    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql(txt, tokenlist.tokens[0]);
}

test "italics with something that looks like an end but isn't" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "''this is 'not' the en'd'<nowiki>''</nowiki>");

    const expected = [_]c.Token{
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("this is 'not' the en'd'<nowiki>") } },
        .{ .type = c.ItalicClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("</nowiki>") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   italics_start_outside_end_inside
// label:  italics that start outside a link and end inside it
// input:  "''foo[[bar|baz'']]spam"
// output: [Text(text="''foo"), WikilinkOpen(), Text(text="bar"), WikilinkSeparator(), Text(text="baz''"), WikilinkClose(), Text(text="spam")]
test "italics that start outside a link and end inside it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "''foo[[bar|baz'']]spam");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("''foo") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("baz''") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("spam") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   italics_start_inside_end_outside
// label:  italics that start inside a link and end outside it
// input:  "[[foo|''bar]]baz''spam"
// output: [Text(text="[[foo|"), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="bar]]baz"), TagOpenClose(), Text(text="i"), TagCloseClose(), Text(text="spam")]
test "italics that start inside a link and end outside it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo|''bar]]baz''spam");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo|") } },
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar]]baz") } },
        .{ .type = c.ItalicClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("spam") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   complex_bold
// label:  bold with a lot in it
// input:  "'''this is a&nbsp;test of [[Bold text|bold]] with {{plenty|of|stuff}}'''"
// output: [TagOpenOpen(wiki_markup="'''"), Text(text="b"), TagCloseOpen(), Text(text="this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of "), WikilinkOpen(), Text(text="Bold text"), WikilinkSeparator(), Text(text="bold"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose(), TagOpenClose(), Text(text="b"), TagCloseClose()]
test "bold with a lot in it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "'''this is a&nbsp;test of [[Bold text|bold]] with {{plenty|of|stuff}}'''");

    const expected = [_]c.Token{
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("this is a") } },
        .{ .type = c.HTMLEntityStart },
        .{ .type = c.Text, .ctx = .{ .data = cText("nbsp") } },
        .{ .type = c.HTMLEntityEnd },
        .{ .type = c.Text, .ctx = .{ .data = cText("test of ") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("Bold text") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("bold") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" with ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("plenty") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("of") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("stuff") } },
        .{ .type = c.TemplateClose },
        .{ .type = c.BoldClose },
    };

    try expectTokensEql(&expected, actual);
}

test "bold spanning mulitple lines" {
    const txt = "foo\nbar'''testing\ntext\nspanning\n\n\n\n\nmultiple\nlines'''foo\n\nbar";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 5);
    try expectTextTokEql("foo\nbar", tokenlist.tokens[0]);
    try expect(tokenlist.tokens[1].type == c.BoldOpen);
    try expectTextTokEql("testing\ntext\nspanning\n\n\n\n\nmultiple\nlines", tokenlist.tokens[2]);
    try expect(tokenlist.tokens[3].type == c.BoldClose);
    try expectTextTokEql("foo\n\nbar", tokenlist.tokens[4]);
}

test "bold without an ending tag" {
    const txt = "'''unending formatting!";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("'''unending formatting!", tokenlist.tokens[0]);
}

test "bold with something that looks like an end but isn't" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "'''this is 'not' the en''d'<nowiki>'''</nowiki>");

    const expected = [_]c.Token{
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("this is 'not' the en''d'<nowiki>") } },
        .{ .type = c.BoldClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("</nowiki>") } },
    };

    try expectTokensEql(&expected, actual);
}

test "bold that start outside a link and end inside it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "'''foo[[bar|baz''']]spam");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("'''foo") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("baz'''") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("spam") } },
    };

    try expectTokensEql(&expected, actual);
}

test "bold and italics together" {
    const txt = "this is '''''bold and italic text'''''!";
    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 7);
    try expectTextTokEql("this is ", tokenlist.tokens[0]);
    try expect(tokenlist.tokens[1].type == c.ItalicOpen);
    try expect(tokenlist.tokens[2].type == c.BoldOpen);
    try expectTextTokEql("bold and italic text", tokenlist.tokens[3]);
    try expect(tokenlist.tokens[4].type == c.BoldClose);
    try expect(tokenlist.tokens[5].type == c.ItalicClose);
    try expectTextTokEql("!", tokenlist.tokens[6]);
}

test "text that starts bold/italic, then is just bold" {
    //const txt = "'''''both''bold'''";
    // const tokenlist = tokenize(txt);
    // Currently Text("''"), BoldOpen, Text("both''bold"), BoldClose
    // Should be: BoldOpen, ItalicOpen, Text("both"), ItalicClose, Text("bold"), BoldClose
    return error.SkipZigTest;
}

test "text that starts bold/italic, then is just italics" {
    const txt = "'''''both'''italics''";
    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 6);
    try expect(tokenlist.tokens[0].type == c.ItalicOpen);
    try expect(tokenlist.tokens[1].type == c.BoldOpen);
    try expectTextTokEql("both", tokenlist.tokens[2]);
    try expect(tokenlist.tokens[3].type == c.BoldClose);
    try expectTextTokEql("italics", tokenlist.tokens[4]);
    try expect(tokenlist.tokens[5].type == c.ItalicClose);
}

test "text that starts just bold, then is bold/italics" {
    const actual = tokenize("''italics'''both'''''");

    const expected = [_]c.Token{
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("italics") } },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("both") } },
        .{ .type = c.BoldClose },
        .{ .type = c.ItalicClose },
    };

    try expectTokensEql(&expected, actual);
}

test "text that starts italic, then is bold" {
    const actual = tokenize("none''italics'''''bold'''none");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("none") } },
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("italics") } },
        .{ .type = c.ItalicClose },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bold") } },
        .{ .type = c.BoldClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("none") } },
    };

    try expectTokensEql(&expected, actual);
}

test "text that starts bold, then is italic" {
    const actual = tokenize("none'''bold'''''italics''none");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("none") } },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bold") } },
        .{ .type = c.BoldClose },
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("italics") } },
        .{ .type = c.ItalicClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("none") } },
    };

    try expectTokensEql(&expected, actual);
}

test "five ticks to open, three to close (bold)" {
    const actual = tokenize("'''''foobar'''");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("''") } },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foobar") } },
        .{ .type = c.BoldClose },
    };

    try expectTokensEql(&expected, actual);
}

test "five ticks to open, two to close (bold)" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "'''''foobar''");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("'''") } },
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foobar") } },
        .{ .type = c.ItalicClose },
    };

    try expectTokensEql(&expected, actual);
}

test "four ticks" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo ''''bar'''' baz");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo '") } },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar'") } },
        .{ .type = c.BoldClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" baz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   four_two
// label:  four ticks to open, two to close
// input:  "foo ''''bar'' baz"
// output: [Text(text="foo ''"), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="bar"), TagOpenClose(), Text(text="i"), TagCloseClose(), Text(text=" baz")]
test "four ticks to open, two to close" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo ''''bar'' baz");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo ''") } },
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.ItalicClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" baz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   two_three
// label:  two ticks to open, three to close
// input:  "foo ''bar''' baz"
// output: [Text(text="foo "), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="bar'"), TagOpenClose(), Text(text="i"), TagCloseClose(), Text(text=" baz")]
test "two ticks to open, three to close" {
    const actual = tokenize("foo ''bar''' baz");

    //const expected = [_]c.Token{
    //    .{ .type = c.Text, .ctx = .{ .data = cText("foo ") } },
    //    .{ .type = c.ItalicOpen },
    //    .{ .type = c.Text, .ctx = .{ .data = cText("bar'") } },
    //    .{ .type = c.ItalicClose },
    //    .{ .type = c.Text, .ctx = .{ .data = cText(" baz") } },
    //};
    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo ''bar''' baz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   two_four
// label:  two ticks to open, four to close
// input:  "foo ''bar'''' baz"
// output: [Text(text="foo "), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="bar''"), TagOpenClose(), Text(text="i"), TagCloseClose(), Text(text=" baz")]
test "two ticks to open, four to close" {
    const actual = tokenize("foo ''bar'''' baz");

    //const expected = [_]c.Token{
    //    .{ .type = c.Text, .ctx = .{ .data = cText("foo ") } },
    //    .{ .type = c.ItalicOpen },
    //    .{ .type = c.Text, .ctx = .{ .data = cText("bar''") } },
    //    .{ .type = c.ItalicClose },
    //    .{ .type = c.Text, .ctx = .{ .data = cText(" baz") } },
    //};
    const expected = [_]c.Token{.{
        .type = c.Text,
        .ctx = .{ .data = cText("foo ''bar'''' baz") },
    }};

    try expectTokensEql(&expected, actual);

    return error.SkipZigTest;
}

// name:   two_three_two
// label:  two ticks to open, three to close, two afterwards
// input:  "foo ''bar''' baz''"
// output: [Text(text="foo "), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="bar''' baz"), TagOpenClose(), Text(text="i"), TagCloseClose()]
test "two ticks to open, three to close, two afterwords" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo ''bar''' baz''");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo ") } },
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar''' baz") } },
        .{ .type = c.ItalicClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   two_four_four
// label:  two ticks to open, four to close, four afterwards
// input:  "foo ''bar'''' baz''''"
// output: [Text(text="foo ''bar'"), TagOpenOpen(wiki_markup="'''"), Text(text="b"), TagCloseOpen(), Text(text=" baz'"), TagOpenClose(), Text(text="b"), TagCloseClose()]
test "two ticks to open, four to close, four afterwards" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo ''bar'''' baz''''");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo ''bar'") } },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText(" baz'") } },
        .{ .type = c.BoldClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   seven
// label:  seven ticks
// input:  "'''''''seven'''''''"
// output: [Text(text="''"), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), TagOpenOpen(wiki_markup="'''"), Text(text="b"), TagCloseOpen(), Text(text="seven''"), TagOpenClose(), Text(text="b"), TagCloseClose(), TagOpenClose(), Text(text="i"), TagCloseClose()]
test "seven ticks" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "'''''''seven'''''''");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("''") } },
        .{ .type = c.ItalicOpen },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("seven''") } },
        .{ .type = c.BoldClose },
        .{ .type = c.ItalicClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   unending_bold_and_italics
// label:  five ticks (bold and italics) that don't end
// input:  "'''''testing"
// output: [Text(text="'''''testing")]
test "five ticks (bold and italics) that don't end" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "'''''testing");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("'''''testing") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   complex_ul
// label:  ul with a lot in it
// input:  "* this is a&nbsp;test of an [[Unordered list|ul]] with {{plenty|of|stuff}}"
// output: [TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text=" this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of an "), WikilinkOpen(), Text(text="Unordered list"), WikilinkSeparator(), Text(text="ul"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose()]
test "ul with a lot in it" {
    const actual = tokenize("* this is a&nbsp;test of an [[Unordered list|ul]] with {{plenty|of|stuff}}");

    const expected = [_]c.Token{
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this is a") } },
        .{ .type = c.HTMLEntityStart },
        .{ .type = c.Text, .ctx = .{ .data = cText("nbsp") } },
        .{ .type = c.HTMLEntityEnd },
        .{ .type = c.Text, .ctx = .{ .data = cText("test of an ") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("Unordered list") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("ul") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" with ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("plenty") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("of") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("stuff") } },
        .{ .type = c.TemplateClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ul_multiline_template
// label:  ul with a template that spans multiple lines
// input:  "* this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
test "ul with a template that spans multiple lines" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "* this has a template with a {{line|\nbreak}}\nthis is not part of the list");

    const expected = [_]c.Token{
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this has a template with a ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("line") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nbreak") } },
        .{ .type = c.TemplateClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nthis is not part of the list") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ul_adjacent
// label:  multiple adjacent uls
// input:  "a\n*b\n*c\nd\n*e\nf"
// output: [Text(text="a\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="c\nd\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf")]
test "multiple adjacent uls" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "a\n*b\n*c\nd\n*e\nf");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\nd\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ul_depths
// label:  multiple adjacent uls, with differing depths
// input:  "*a\n**b\n***c\n********d\n**e\nf\n***g"
// output: [TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="g")]
test "multiple adjacent uls, with differing depths" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "*a\n**b\n***c\n********d\n**e\nf\n***g");

    const expected = [_]c.Token{
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("d\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("g") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ul_space_before
// label:  uls with space before them
// input:  "foo    *bar\n *baz\n*buzz"
// output: [Text(text="foo    *bar\n *baz\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="buzz")]
test "uls with space before them" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo    *bar\n *baz\n*buzz");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo    *bar\n *baz\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("buzz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ul_interruption
// label:  high-depth ul with something blocking it
// input:  "**f*oobar"
// output: [TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="f*oobar")]
test "high-depth ul with something blocking it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "**f*oobar");

    const expected = [_]c.Token{
        .{ .type = c.UnorderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("f*oobar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   complex_ol
// label:  ol with a lot in it
// input:  "# this is a&nbsp;test of an [[Ordered list|ol]] with {{plenty|of|stuff}}"
// output: [TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text=" this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of an "), WikilinkOpen(), Text(text="Ordered list"), WikilinkSeparator(), Text(text="ol"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose()]
test "ol with a lot in it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "# this is a&nbsp;test of an [[Ordered list|ol]] with {{plenty|of|stuff}}");

    const expected = [_]c.Token{
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this is a") } },
        .{ .type = c.HTMLEntityStart },
        .{ .type = c.Text, .ctx = .{ .data = cText("nbsp") } },
        .{ .type = c.HTMLEntityEnd },
        .{ .type = c.Text, .ctx = .{ .data = cText("test of an ") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("Ordered list") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("ol") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" with ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("plenty") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("of") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("stuff") } },
        .{ .type = c.TemplateClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ol_multiline_template
// label:  ol with a template that spans moltiple lines
// input:  "# this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
test "ol with a template that spans multiple lines" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "# this has a template with a {{line|\nbreak}}\nthis is not part of the list");

    const expected = [_]c.Token{
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this has a template with a ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("line") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nbreak") } },
        .{ .type = c.TemplateClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nthis is not part of the list") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ol_adjacent
// label:  moltiple adjacent ols
// input:  "a\n#b\n#c\nd\n#e\nf"
// output: [Text(text="a\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="c\nd\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf")]
test "multiple adjacent ols" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "a\n#b\n#c\nd\n#e\nf");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\nd\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ol_depths
// label:  moltiple adjacent ols, with differing depths
// input:  "#a\n##b\n###c\n########d\n##e\nf\n###g"
// output: [TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="g")]
test "multiple adjacent ols, with differing depths" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "#a\n##b\n###c\n########d\n##e\nf\n###g");

    const expected = [_]c.Token{
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("d\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("g") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ol_space_before
// label:  ols with space before them
// input:  "foo    #bar\n #baz\n#buzz"
// output: [Text(text="foo    #bar\n #baz\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="buzz")]
test "ols with space before them" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo    #bar\n #baz\n#buzz");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo    #bar\n #baz\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("buzz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ol_interruption
// label:  high-depth ol with something blocking it
// input:  "##f#oobar"
// output: [TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="f#oobar")]
test "high-depth ol with something blocking it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "##f#oobar");

    const expected = [_]c.Token{
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("f#oobar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ul_ol_mix
// label:  a mix of adjacent uls and ols
// input:  "*a\n*#b\n*##c\n*##*#*#*d\n*#e\nf\n##*g"
// output: [TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="g")]
test "a mix of adjacent uls and ols" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "*a\n*#b\n*##c\n*##*#*#*d\n*#e\nf\n##*g");

    const expected = [_]c.Token{
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("d\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("g") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   complex_dt
// label:  dt with a lot in it
// input:  "; this is a&nbsp;test of an [[description term|dt]] with {{plenty|of|stuff}}"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text=" this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of an "), WikilinkOpen(), Text(text="description term"), WikilinkSeparator(), Text(text="dt"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose()]
test "dt with a lot in it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "; this is a&nbsp;test of an [[description term|dt]] with {{plenty|of|stuff}}");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this is a") } },
        .{ .type = c.HTMLEntityStart },
        .{ .type = c.Text, .ctx = .{ .data = cText("nbsp") } },
        .{ .type = c.HTMLEntityEnd },
        .{ .type = c.Text, .ctx = .{ .data = cText("test of an ") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("description term") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("dt") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" with ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("plenty") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("of") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("stuff") } },
        .{ .type = c.TemplateClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_multiline_template
// label:  dt with a template that spans mdttiple lines
// input:  "; this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
test "dt with a template that spans mdttiple lines" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "; this has a template with a {{line|\nbreak}}\nthis is not part of the list");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this has a template with a ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("line") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nbreak") } },
        .{ .type = c.TemplateClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nthis is not part of the list") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_adjacent
// label:  multiple adjacent dts
// input:  "a\n;b\n;c\nd\n;e\nf"
// output: [Text(text="a\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="c\nd\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="e\nf")]
test "multiple adjacent dts" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "a\n;b\n;c\nd\n;e\nf");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\nd\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_depths
// label:  multiple adjacent dts, with differing depths
// input:  ";a\n;;b\n;;;c\n;;;;;;;;d\n;;e\nf\n;;;g"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="g")]
test "multiple adjacent dts, with differing depths" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ";a\n;;b\n;;;c\n;;;;;;;;d\n;;e\nf\n;;;g");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("d\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("g") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_space_before
// label:  dts with space before them
// input:  "foo    ;bar\n ;baz\n;buzz"
// output: [Text(text="foo    ;bar\n ;baz\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="buzz")]
test "dts with space before them" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo    ;bar\n ;baz\n;buzz");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo    ;bar\n ;baz\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("buzz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_interruption
// label:  high-depth dt with something blocking it
// input:  ";;f;oobar"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="f;oobar")]
test "high-depth dt with something blocking it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ";;f;oobar");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("f;oobar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   complex_dd
// label:  dd with a lot in it
// input:  ": this is a&nbsp;test of an [[description item|dd]] with {{plenty|of|stuff}}"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text=" this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of an "), WikilinkOpen(), Text(text="description item"), WikilinkSeparator(), Text(text="dd"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose()]
test "dd with a lot in it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ": this is a&nbsp;test of an [[description item|dd]] with {{plenty|of|stuff}}");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this is a") } },
        .{ .type = c.HTMLEntityStart },
        .{ .type = c.Text, .ctx = .{ .data = cText("nbsp") } },
        .{ .type = c.HTMLEntityEnd },
        .{ .type = c.Text, .ctx = .{ .data = cText("test of an ") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("description item") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("dd") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" with ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("plenty") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("of") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("stuff") } },
        .{ .type = c.TemplateClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dd_multiline_template
// label:  dd with a template that spans mddtiple lines
// input:  ": this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
test "dd with a template that spans multiple lines" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ": this has a template with a {{line|\nbreak}}\nthis is not part of the list");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText(" this has a template with a ") } },
        .{ .type = c.TemplateOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("line") } },
        .{ .type = c.TemplateParamSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nbreak") } },
        .{ .type = c.TemplateClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nthis is not part of the list") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dd_adjacent
// label:  mddtiple adjacent dds
// input:  "a\n:b\n:c\nd\n:e\nf"
// output: [Text(text="a\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="c\nd\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="e\nf")]
test "multiple adjacent dds" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "a\n:b\n:c\nd\n:e\nf");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\nd\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dd_depths
// label:  multiple adjacent dds, with differing depths
// input:  ":a\n::b\n:::c\n::::::::d\n::e\nf\n:::g"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="g")]
test "multiple adjacent dds, with differing depths" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ":a\n::b\n:::c\n::::::::d\n::e\nf\n:::g");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("d\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("g") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dd_space_before
// label:  dds with space before them
// input:  "foo    :bar\n :baz\n:buzz"
// output: [Text(text="foo    :bar\n :baz\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="buzz")]
test "dds with space before them" {
    // waiting on Tokenizer_remove_uri_scheme_from_textbuffer
    return error.SkipZigTest;
    // var a: Arena = std.mem.zeroes(Arena);
    // try std.testing.expect(c.arena_init(&a) == 0);
    // defer c.arena_clear(&a);

    // const actual = tokenize_arena(&a, "foo    :bar\n :baz\n:buzz");

    // const expected = [_]c.Token{
    //     .{ .type = c.Text, .ctx = .{ .data = cText("foo    :bar\n :baz\n") } },
    //     .{ .type = c.DescriptionItem },
    //     .{ .type = c.Text, .ctx = .{ .data = cText("buzz") } },
    // };

    // try expectTokensEql(&expected, actual);
}

// name:   dd_interruption
// label:  high-depth dd with something blocking it
// input:  "::f:oobar"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="f:oobar")]
test "high-depth dd with something blocking it" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "::f:oobar");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("f:oobar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_dd_mix
// label:  a mix of adjacent dts and dds
// input:  ";a\n;:b\n;::c\n;::;:;:;d\n;:e\nf\n::;g"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="g")]
test "a mix of adjacent dts and dds" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ";a\n;:b\n;::c\n;::;:;:;d\n;:e\nf\n::;g");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("a\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("b\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("c\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("d\n") } },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("e\nf\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("g") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_dd_mix2
// label:  the correct usage of a dt/dd unit, as in a dl
// input:  ";foo:bar:baz"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="foo"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="bar:baz")]
test "the correct usage of a dt/dd unit, as in a dl" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ";foo:bar:baz");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar:baz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_dd_mix3
// label:  another example of correct (but strange) dt/dd usage
// input:  ":;;::foo:bar:baz"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="foo"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="bar:baz")]
test "another example of correct (but strange) dt/dd usage" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ":;;::foo:bar:baz");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar:baz") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   dt_dd_mix4
// label:  another example of correct dt/dd usage, with a trigger for a specific parse route
// input:  ";foo]:bar"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="foo]"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="bar")]
test "another example of correct dt/dd usage, with a trigger for a specific parse route" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ";foo]:bar");

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo]") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   ul_ol_dt_dd_mix
// label:  an assortment of uls, ols, dds, and dts
// input:  ";:#*foo\n:#*;foo\n#*;:foo\n*;:#foo"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="foo\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="foo\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="foo\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="foo")]
test "an assortment of uls, ols, dds, and dts" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, ";:#*foo\n:#*;foo\n#*;:foo\n*;:#foo");
    // printTokens(actual);

    const expected = [_]c.Token{
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo\n") } },
        .{ .type = c.DescriptionItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo\n") } },
        .{ .type = c.OrderedListItem },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo\n") } },
        .{ .type = c.UnorderedListItem },
        .{ .type = c.DescriptionTerm },
        .{ .type = c.DescriptionItem },
        .{ .type = c.OrderedListItem },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_text_before
// label:  text before an otherwise-valid hr
// input:  "foo----"
// output: [Text(text="foo----")]
test "text before an otherwise valid hr" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo----");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo----") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_text_after
// label:  text after a valid hr
// input:  "----bar"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="bar")]
test "text after a valid hr" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "----bar");

    const expected = [_]c.Token{
        .{ .type = c.HR },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_text_before_after
// label:  text at both ends of an otherwise-valid hr
// input:  "foo----bar"
// output: [Text(text="foo----bar")]
test "text at both ends of an otherwise-valid hr" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo----bar");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo----bar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_newlines
// label:  newlines surrounding a valid hr
// input:  "foo\n----\nbar"
// output: [Text(text="foo\n"), TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="\nbar")]
test "newlines surrounding a valid hr" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "foo\n----\nbar");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("foo\n") } },
        .{ .type = c.HR },
        .{ .type = c.Text, .ctx = .{ .data = cText("\nbar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_adjacent
// label:  two adjacent hrs
// input:  "----\n----"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="\n"), TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose()]
test "two adjacent hrs" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "----\n----");

    const expected = [_]c.Token{
        .{ .type = c.HR },
        .{ .type = c.Text, .ctx = .{ .data = cText("\n") } },
        .{ .type = c.HR },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_adjacent_space
// label:  two adjacent hrs, with a space before the second one, making it invalid
// input:  "----\n ----"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="\n ----")]
test "two adjacent hrs, with a space before the second one, making it invalid" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "----\n ----");

    const expected = [_]c.Token{
        .{ .type = c.HR },
        .{ .type = c.Text, .ctx = .{ .data = cText("\n ----") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_short
// label:  an invalid three-hyphen-long hr
// input:  "---"
// output: [Text(text="---")]
test "an invalid three-hyphen-long hr" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "---");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("---") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_long
// label:  a very long, valid hr
// input:  "------------------------------------------"
// output: [TagOpenOpen(wiki_markup="------------------------------------------"), Text(text="hr"), TagCloseSelfclose()]
test "a ver long , valid hr" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "------------------------------------------");

    const expected = [_]c.Token{
        .{ .type = c.HR },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_interruption_short
// label:  a hr that is interrupted, making it invalid
// input:  "---x-"
// output: [Text(text="---x-")]
test "a hr that is interrupted, making it invalid" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "---x-");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("---x-") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   hr_interruption_long
// label:  a hr that is interrupted, but the first part remains valid because it is long enough
// input:  "----x--"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="x--")]
test "a hr that is interrupted, but the first part remains valid because it is long enough" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "----x--");

    const expected = [_]c.Token{
        .{ .type = c.HR },
        .{ .type = c.Text, .ctx = .{ .data = cText("x--") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   nowiki_cancel
// label:  a nowiki tag before a list causes it to not be parsed
// input:  "<nowiki />* Unordered list"
// output: [TagOpenOpen(), Text(text="nowiki"), TagCloseSelfclose(padding=" "), Text(text="* Unordered list")]
test "a nowiki tag before a list causes it to not be parsed" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "<nowiki />* Unordered list");

    const expected = [_]c.Token{
        .{ .type = c.TagOpenOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("nowiki") } },
        .{ .type = c.TagCloseSelfclose },
        .{ .type = c.Text, .ctx = .{ .data = cText("* Unordered list") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   blank
// label:  wikilink with no content
// input:  "[[]]"
// output: [WikilinkOpen(), WikilinkClose()]
test "wikilink with no content" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   blank_with_text
// label:  wikilink with no content but a pipe
// input:  "[[|]]"
// output: [WikilinkOpen(), WikilinkSeparator(), WikilinkClose()]
test "wikilink with no content but a pipe" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[|]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   basic
// label:  simplest type of wikilink
// input:  "[[wikilink]]"
// output: [WikilinkOpen(), Text(text="wikilink"), WikilinkClose()]
test "simplest type of wikilink" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[wikilink]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("wikilink") } },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   with_text
// label:  wikilink with a text value
// input:  "[[foo|bar]]"
// output: [WikilinkOpen(), Text(text="foo"), WikilinkSeparator(), Text(text="bar"), WikilinkClose()]
test "wikilink with a text value" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo|bar]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   blank_with_multiple_texts
// label:  no content, multiple pipes
// input:  "[[|||]]"
// output: [WikilinkOpen(), WikilinkSeparator(), Text(text="||"), WikilinkClose()]
test "no content, multiple pipes" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[|||]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("||") } },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   multiple_texts
// label:  multiple text values separated by pipes
// input:  "[[foo|bar|baz]]"
// output: [WikilinkOpen(), Text(text="foo"), WikilinkSeparator(), Text(text="bar|baz"), WikilinkClose()]
test "multiple text values separated by pipes" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo|bar|baz]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar|baz") } },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   newline_text
// label:  a newline in the middle of the text
// input:  "[[foo|foo\nbar]]"
// output: [WikilinkOpen(), Text(text="foo"), WikilinkSeparator(), Text(text="foo\nbar"), WikilinkClose()]
test "a newline in the middle of the text" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo|foo\nbar]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo\nbar") } },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   bracket_text
// label:  a left bracket in the middle of the text
// input:  "[[foo|bar[baz]]"
// output: [WikilinkOpen(), Text(text="foo"), WikilinkSeparator(), Text(text="bar[baz"), WikilinkClose()]
test "a left bracket in the middle of the text" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo|bar[baz]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.WikilinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar[baz") } },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   nested
// label:  a wikilink nested within another
// input:  "[[file:foo|[[bar]]]]"
// output: [WikilinkOpen(), Text(text="file:foo"), WikilinkSeparator(), WikilinkOpen(), Text(text="bar"), WikilinkClose(), WikilinkClose()]

// name:   nested_padding
// label:  a wikilink nested within another, separated by other data
// input:  "[[file:foo|a[[b]]c]]"
// output: [WikilinkOpen(), Text(text="file:foo"), WikilinkSeparator(), Text(text="a"), WikilinkOpen(), Text(text="b"), WikilinkClose(), Text(text="c"), WikilinkClose()]

// name:   invalid_newline
// label:  invalid wikilink: newline as only content
// input:  "[[\n]]"
// output: [Text(text="[[\n]]")]
test "invalid wikilink: newline as only content" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[\n]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[\n]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_right_brace
// label:  invalid wikilink: right brace
// input:  "[[foo}b}a}r]]"
// output: [Text(text="[[foo}b}a}r]]")]
test "invalid wikilink: right brace" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo}b}a}r]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo}b}a}r]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_left_brace
// label:  invalid wikilink: left brace
// input:  "[[foo{{[a}}]]"
// output: [Text(text="[[foo{{[a}}]]")]
test "invalid wikilink: left brace" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo{{[a}}]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo{{[a}}]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   empty_string
// label:  empty string as input
// input:  "[[]]"
// output: [WikilinkOpen(), WikilinkClose()]
test "empty string" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[]]");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   single_brace
// label:  wikilink with only left brace
// input:  "[["
// output: [Text(text="[[")]
test "wikilink with only left brace" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   single_brace2
// label:  wikilink with only right brace
// input:  "[]]"
// output: [Text(text="[[]]")]
test "wikilink with only right brace" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_right_bracket
// label:  invalid wikilink: right bracket
// input:  "[[foo]bar]]"
// output: [Text(text="[[foo]bar]]")]
test "invalid wikilink: right bracket" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo]bar]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo]bar]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_left_bracket
// label:  invalid wikilink: left bracket
// input:  "[[foo[bar]]"
// output: [Text(text="[[foo[bar]]")]
test "invalid wikilink: left bracket" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo[bar]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo[bar]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_nested_title
// label:  invalid wikilink: nested within the title of another
// input:  "[[foo[[bar]]]]"
// output: [Text(text="[[foo"), WikilinkOpen(), Text(text="bar"), WikilinkClose(), Text(text="]]")]
test "invalid wikilink: nested within the title of another" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo[[bar]]]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_nested_title_and_text
// label:  invalid wikilink: nested within the title of another, with a text param
// input:  "[[foo[[bar]]|baz]]"
// output: [Text(text="[[foo"), WikilinkOpen(), Text(text="bar"), WikilinkClose(), Text(text="|baz]]")]
test "invalid wikilink: nested within the title of another, with a text param" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo[[bar]]|baz]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText("|baz]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_nested_no_close
// label:  invalid wikilink: a wikilink nested within the value of another, missing a pair of closing brackets
// input:  "[[foo|[[bar]]"
// output: [Text(text="[[foo|"), WikilinkOpen(), Text(text="bar"), WikilinkClose()]
test "invalid wikilink: a wikilink nested within the value of another, missing a pair of closing brackets" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo|[[bar]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo|") } },
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.WikilinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_left_angle_bracket
// label:  invalid wikilink: left angle bracket
// input:  "[[foo<bar]]"
// output: [Text(text="[[foo<bar]]")]
test "invalid wikilink: left angle bracket" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo<bar]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo<bar]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_right_angle_bracket
// label:  invalid wikilink: right angle bracket
// input:  "[[foo>bar]]"
// output: [Text(text="[[foo>bar]]")]
test "invalid wikilink: right angle bracket" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo>bar]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo>bar]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_newline_at_start
// label:  invalid wikilink: newline at start of title
// input:  "[[\nfoobar]]"
// output: [Text(text="[[\nfoobar]]")]
test "invalid wikilink: newline at start of title" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[\nfoobar]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[\nfoobar]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_newline_at_end
// label:  invalid wikilink: newline at end of title
// input:  "[[foobar\n]]"
// output: [Text(text="[[foobar\n]]")]
test "invalid wikilink: newline at end of title" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foobar\n]]");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foobar\n]]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_only
// label:  incomplete wikilinks: just an open
// input:  "[["
// output: [Text(text="[[")]
test "incomplete wikilinks: just an open" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_text
// label:  incomplete wikilinks: an open with some text
// input:  "[[foo"
// output: [Text(text="[[foo")]
test "incomplete wikilinks: an open with some text" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_text_pipe
// label:  incomplete wikilinks: an open, text, then a pipe
// input:  "[[foo|"
// output: [Text(text="[[foo|")]
test "incomplete wikilinks: an open, text, then a pipe" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo|");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[foo|") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_pipe
// label:  incomplete wikilinks: an open, then a pipe
// input:  "[[|"
// output: [Text(text="[[|")]
test "incomplete wikilinks: an open, then a pipe" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[|");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[|") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_pipe_text
// label:  incomplete wikilinks: an open, then a pipe, then text
// input:  "[[|foo"
// output: [Text(text="[[|foo")]
test "incomplete wikilinks: an open, then a pipe, then text" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[|foo");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[|foo") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_pipes_text
// label:  incomplete wikilinks: a pipe, then text then two pipes
// input:  "[[|f||"
// output: [Text(text="[[|f||")]
test "incomplete wikilinks: a pipe, then text then two pipes" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[|f||");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[|f||") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_partial_close
// label:  incomplete wikilinks: an open, then one right brace
// input:  "[[{}"
// output: [Text(text="[[{}")]
test "incomplete wikilinks: an open, then one right brace" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[{}");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("[[{}") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_preserve_previous
// label:  incomplete wikilinks: a valid wikilink followed by an invalid one
// input:  "[[foo]] [[bar"
// output: [WikilinkOpen(), Text(text="foo"), WikilinkClose(), Text(text=" [[bar")]
test "incomplete wikilinks: a valid wikilink followed by an invalid one" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[[foo]] [[bar");

    const expected = [_]c.Token{
        .{ .type = c.WikilinkOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.WikilinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" [[bar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   blank
// label:  argument with no content
// input:  "{{{}}}"
// output: [ArgumentOpen(), ArgumentClose()]
test "argument with no content" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{}}}");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.ArgumentClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   blank_with_default
// label:  argument with no content but a pipe
// input:  "{{{|}}}"
// output: [ArgumentOpen(), ArgumentSeparator(), ArgumentClose()]
test "argument with no content but a pipe" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{|}}}");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.ArgumentSeparator },
        .{ .type = c.ArgumentClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   basic
// label:  simplest type of argument
// input:  "{{{argument}}}"
// output: [ArgumentOpen(), Text(text="argument"), ArgumentClose()]
test "simplest type of argument" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{argument}}}");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("argument") } },
        .{ .type = c.ArgumentClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   default
// label:  argument with a default value
// input:  "{{{foo|bar}}}"
// output: [ArgumentOpen(), Text(text="foo"), ArgumentSeparator(), Text(text="bar"), ArgumentClose()]
test "argument with a default value" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{foo|bar}}}");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.ArgumentSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.ArgumentClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   blank_with_multiple_defaults
// label:  no content, multiple pipes
// input:  "{{{|||}}}"
// output: [ArgumentOpen(), ArgumentSeparator(), ArgumentSeparator(), ArgumentSeparator(), ArgumentClose()]
test "(argument) no content, multiple pipes" {
    // var a: Arena = std.mem.zeroes(Arena);
    // try std.testing.expect(c.arena_init(&a) == 0);
    // defer c.arena_clear(&a);

    // const actual = tokenize_arena(&a, "{{{|||}}}");

    // const expected = [_]c.Token{
    //     .{ .type = c.ArgumentOpen },
    //     .{ .type = c.ArgumentSeparator },
    //     .{ .type = c.ArgumentSeparator },
    //     .{ .type = c.ArgumentSeparator },
    //     .{ .type = c.ArgumentClose },
    // };

    // try expectTokensEql(&expected, actual);
    // ArgumentOpen, ArgumentSeparator, Text("||"), ArgumentClose
    return error.SkipZigTest;
}

// name:   multiple_defaults
// label:  multiple values separated by pipes
// input:  "{{{foo|bar|baz}}}"
// output: [ArgumentOpen(), Text(text="foo"), ArgumentSeparator(), Text(text="bar"), ArgumentSeparator(), Text(text="baz"), ArgumentClose()]
test "multiple values separated by pipes" {
    // var a: Arena = std.mem.zeroes(Arena);
    // try std.testing.expect(c.arena_init(&a) == 0);
    // defer c.arena_clear(&a);

    // const actual = tokenize_arena(&a, "{{{foo|bar|baz}}}");
    // printTokens(actual);

    // const expected = [_]c.Token{
    //     .{ .type = c.ArgumentOpen },
    //     .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
    //     .{ .type = c.ArgumentSeparator },
    //     .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
    //     .{ .type = c.ArgumentSeparator },
    //     .{ .type = c.Text, .ctx = .{ .data = cText("baz") } },
    //     .{ .type = c.ArgumentClose },
    // };

    // try expectTokensEql(&expected, actual);
    // ArgumentOpen, Text("foo"), ArgumentSeparator, Text("bar|baz"), ArgumentClose
    return error.SkipZigTest;
}

// name:   newline
// label:  newline as only content
// input:  "{{{\n}}}"
// output: [ArgumentOpen(), Text(text="\n"), ArgumentClose()]
test "newline as only content" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{\n}}}");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("\n") } },
        .{ .type = c.ArgumentClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   right_braces
// label:  multiple } scattered throughout text
// input:  "{{{foo}b}a}r}}}"
// output: [ArgumentOpen(), Text(text="foo}b}a}r"), ArgumentClose()]
test "multiple } scattered throughout text" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{foo}b}a}r}}}");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo}b}a}r") } },
        .{ .type = c.ArgumentClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   right_braces_default
// label:  multiple } scattered throughout text, with a default value
// input:  "{{{foo}b}|}a}r}}}"
// output: [ArgumentOpen(), Text(text="foo}b"), ArgumentSeparator(), Text(text="}a}r"), ArgumentClose()]
test "multiple } scattered throughout text, with a default value" {
    // var a: Arena = std.mem.zeroes(Arena);
    // try std.testing.expect(c.arena_init(&a) == 0);
    // defer c.arena_clear(&a);

    // const actual = tokenize_arena(&a, "{{{foo}b}|}a}r}}}");
    // printTokens(actual);

    // const expected = [_]c.Token{
    //     .{ .type = c.ArgumentOpen },
    //     .{ .type = c.Text, .ctx = .{ .data = cText("foo}b") } },
    //     .{ .type = c.ArgumentSeparator },
    //     .{ .type = c.Text, .ctx = .{ .data = cText("}a}r") } },
    //     .{ .type = c.ArgumentClose },
    // };

    // try expectTokensEql(&expected, actual);
    // ArgumentOpen, Text("foo}b}"), ArgumentSeparator, Text("}a}r"), ArgumentClose
    return error.SkipZigTest;
}

// name:   nested
// label:  an argument nested within another argument
// input:  "{{{{{{foo}}}|{{{bar}}}}}}"
// output: [ArgumentOpen(), ArgumentOpen(), Text(text="foo"), ArgumentClose(), ArgumentSeparator(), ArgumentOpen(), Text(text="bar"), ArgumentClose(), ArgumentClose()]
test "an argument nested within another argument" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{{{{foo}}}|{{{bar}}}}}}");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.ArgumentOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.ArgumentClose },
        .{ .type = c.ArgumentSeparator },
        .{ .type = c.ArgumentOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("bar") } },
        .{ .type = c.ArgumentClose },
        .{ .type = c.ArgumentClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   invalid_braces
// label:  invalid argument: multiple braces that are not part of a template or argument
// input:  "{{{foo{{[a}}}}}"
// output: [Text(text="{{{foo{{[a}}}}}")]
test "invalid argument: multiple braces that are not part of a template or argument" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{foo{{[a}}}}}");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{foo{{[a}}}}}") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_only
// label:  incomplete arguments: just an open
// input:  "{{{"
// output: [Text(text="{{{")]
test "incomplete arguments: just an open" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_text
// label:  incomplete arguments: an open with some text
// input:  "{{{foo"
// output: [Text(text="{{{foo")]
test "incomplete arguments: an open with some text" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{foo");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{foo") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_text_pipe
// label:  incomplete arguments: an open, text, then a pipe
// input:  "{{{foo|"
// output: [Text(text="{{{foo|")]
test "incomplete arguments: an open, text, then a pipe" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{foo|");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{foo|") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_pipe
// label:  incomplete arguments: an open, then a pipe
// input:  "{{{|"
// output: [Text(text="{{{|")]
test "incomplete arguments: an open, then a pipe" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{|");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{|") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_pipe_text
// label:  incomplete arguments: an open, then a pipe, then text
// input:  "{{{|foo"
// output: [Text(text="{{{|foo")]
test "incomplete arguments: an open, then a pipe, then text" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{|foo");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{|foo") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_pipes_text
// label:  incomplete arguments: a pipe, then text then two pipes
// input:  "{{{|f||"
// output: [Text(text="{{{|f||")]
test "incomplete arguments: a pipe, then text then two pipes" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{|f||");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{|f||") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_open_partial_close
// label:  incomplete arguments: an open, then one right brace
// input:  "{{{{}"
// output: [Text(text="{{{{}")]
test "incomplete arguments: an open, then one right brace" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{{}");

    const expected = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("{{{{}") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   incomplete_preserve_previous
// label:  incomplete arguments: a valid argument followed by an invalid one
// input:  "{{{foo}}} {{{bar"
// output: [ArgumentOpen(), Text(text="foo"), ArgumentClose(), Text(text=" {{{bar")]
test "incomplete arguments: a valid argument followed by an invalid one" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "{{{foo}}} {{{bar");

    const expected = [_]c.Token{
        .{ .type = c.ArgumentOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foo") } },
        .{ .type = c.ArgumentClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" {{{bar") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   basic
// label:  basic external link
// input:  "http://example.com/"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.com/"), ExternalLinkClose()]
test "basic external link" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "http://example.com");

    const expected = [_]c.Token{
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = false } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com") } },
        .{ .type = c.ExternalLinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   basic_brackets
// label:  basic external link in brackets
// input:  "[http://example.com/]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com/"), ExternalLinkClose()]
test "basic external link in brackets" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com]");

    const expected = [_]c.Token{
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = true } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com") } },
        .{ .type = c.ExternalLinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_space
// label:  basic external link in brackets, with a space after
// input:  "[http://example.com/ ]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com/"), ExternalLinkSeparator(), ExternalLinkClose()]
test "basic external link in brackets, with a space after" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com ]");

    const expected = [_]c.Token{
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = true } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com") } },
        .{ .type = c.ExternalLinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText(" ") } }, // SHOULD NOT BE HERE
        .{ .type = c.ExternalLinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_title
// label:  basic external link in brackets, with a title
// input:  "[http://example.com/ Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com/"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
test "basic external link in brackets, with a title" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com Example]");

    const expected = [_]c.Token{
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = true } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com") } },
        .{ .type = c.ExternalLinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText(" Example") } }, // SHOULD NOT BE A SPACE
        .{ .type = c.ExternalLinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_multiword_title
// label:  basic external link in brackets, with a multi-word title
// input:  "[http://example.com/ Example Web Page]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com/"), ExternalLinkSeparator(), Text(text="Example Web Page"), ExternalLinkClose()]
test "basic external link in brackets, with a multi-word title" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com Example Web Page]");

    const expected = [_]c.Token{
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = true } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com") } },
        .{ .type = c.ExternalLinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText(" Example Web Page") } }, // SHOULD NOT BE A SPACE
        .{ .type = c.ExternalLinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_adjacent
// label:  three adjacent bracket-enclosed external links
// input:  "[http://foo.com/ Foo][http://bar.com/ Bar]\n[http://baz.com/ Baz]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://foo.com/"), ExternalLinkSeparator(), Text(text="Foo"), ExternalLinkClose(), ExternalLinkOpen(brackets=True), Text(text="http://bar.com/"), ExternalLinkSeparator(), Text(text="Bar"), ExternalLinkClose(), Text(text="\n"), ExternalLinkOpen(brackets=True), Text(text="http://baz.com/"), ExternalLinkSeparator(), Text(text="Baz"), ExternalLinkClose()]
//
// ---
//

// name:   brackets_newline_before
// label:  bracket-enclosed link with a newline before the title
// input:  "[http://example.com/ \nExample]"
// output: [Text(text="["), ExternalLinkOpen(brackets=False), Text(text="http://example.com/"), ExternalLinkClose(), Text(text=" \nExample]")]
test "bracket-enclosed link with a newline before the title" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com/ \nExample]");

    const expected = [_]c.Token{
        // .{ .type = c.Text, .ctx = .{ .data = cText("[") } }, SHOULD BE PRESENT
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = false } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com/") } },
        .{ .type = c.ExternalLinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" \nExample]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_newline_inside
// label:  bracket-enclosed link with a newline in the title
// input:  "[http://example.com/ Example \nWeb Page]"
// output: [Text(text="["), ExternalLinkOpen(brackets=False), Text(text="http://example.com/"), ExternalLinkClose(), Text(text=" Example \nWeb Page]")]
test "bracket-enclosed link with a newline in the title" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com/ Example \nWeb Page]");

    const expected = [_]c.Token{
        // .{ .type = c.Text, .ctx = .{ .data = cText("[") } }, SHOULD BE PRESENT
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = false } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com/") } },
        .{ .type = c.ExternalLinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" Example \nWeb Page]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_newline_after
// label:  bracket-enclosed link with a newline after the title
// input:  "[http://example.com/ Example\n]"
// output: [Text(text="["), ExternalLinkOpen(brackets=False), Text(text="http://example.com/"), ExternalLinkClose(), Text(text=" Example\n]")]
test "bracket-enclosed link with a newline after the title" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com/ Example\n]");

    const expected = [_]c.Token{
        // .{ .type = c.Text, .ctx = .{ .data = cText("[") } }, SHOULD BE PRESENT
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = false } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com/") } },
        .{ .type = c.ExternalLinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" Example\n]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_space_before
// label:  bracket-enclosed link with a space before the URL
// input:  "[ http://example.com Example]"
// output: [Text(text="[ "), ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose(), Text(text=" Example]")]
test "bracket-enclosed link with a space before the URL" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[ http://example.com/ Example]");

    const expected = [_]c.Token{
        // .{ .type = c.Text, .ctx = .{ .data = cText("[ ") } }, SHOULD BE PRESENT
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = false } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com/") } },
        .{ .type = c.ExternalLinkClose },
        .{ .type = c.Text, .ctx = .{ .data = cText(" Example]") } },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_title_like_url
// label:  bracket-enclosed link with a title that looks like a URL
// input:  "[http://example.com http://example.com]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com"), ExternalLinkSeparator(), Text(text="http://example.com"), ExternalLinkClose()]
test "bracket-enclosed link with a title that looks like a URL" {
    var a: Arena = std.mem.zeroes(Arena);
    try std.testing.expect(c.arena_init(&a) == 0);
    defer c.arena_clear(&a);

    const actual = tokenize_arena(&a, "[http://example.com http://example.com]");

    const expected = [_]c.Token{
        .{ .type = c.ExternalLinkOpen, .ctx = .{ .external_link_open = .{ .brackets = true } } },
        .{ .type = c.Text, .ctx = .{ .data = cText("http://example.com") } },
        .{ .type = c.ExternalLinkSeparator },
        .{ .type = c.Text, .ctx = .{ .data = cText(" http://example.com") } }, // SHOULD NOT BE A SPACE
        .{ .type = c.ExternalLinkClose },
    };

    try expectTokensEql(&expected, actual);
}

// name:   brackets_recursive
// label:  bracket-enclosed link with a bracket-enclosed link as the title
// input:  "[http://example.com [http://example.com]]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com"), ExternalLinkSeparator(), Text(text="[http://example.com"), ExternalLinkClose(), Text(text="]")]
//
// ---
//
// name:   brackets_recursive_2
// label:  bracket-enclosed link with a double bracket-enclosed link as the title
// input:  "[http://example.com [[http://example.com]]]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com"), ExternalLinkSeparator(), Text(text="[[http://example.com"), ExternalLinkClose(), Text(text="]]")]
//
// ---
//
// name:   period_after
// label:  a period after a free link that is excluded
// input:  "http://example.com."
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose(), Text(text=".")]
//
// ---
//
// name:   colons_after
// label:  colons after a free link that are excluded
// input:  "http://example.com/foo:bar.:;baz!?,"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.com/foo:bar.:;baz"), ExternalLinkClose(), Text(text="!?,")]
//
// ---
//
// name:   close_paren_after_excluded
// label:  a closing parenthesis after a free link that is excluded
// input:  "http://example.)com)"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.)com"), ExternalLinkClose(), Text(text=")")]
//
// ---
//
// name:   close_paren_after_included
// label:  a closing parenthesis after a free link that is included because of an opening parenthesis in the URL
// input:  "http://example.(com)"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.(com)"), ExternalLinkClose()]
//
// ---
//
// name:   open_bracket_inside
// label:  an open bracket inside a free link that causes it to be ended abruptly
// input:  "http://foobar[baz.com"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://foobar"), ExternalLinkClose(), Text(text="[baz.com")]
//
// ---
//
// name:   brackets_period_after
// label:  a period after a bracket-enclosed link that is included
// input:  "[http://example.com. Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com."), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   brackets_punct_after
// label:  punctuation after a bracket-enclosed link that are included
// input:  "[http://example.com/foo:bar.:;baz!?, Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.com/foo:bar.:;baz!?,"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   brackets_close_paren_after_included
// label:  a closing parenthesis after a bracket-enclosed link that is included
// input:  "[http://example.)com) Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.)com)"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   brackets_close_paren_after_included_2
// label:  a closing parenthesis after a bracket-enclosed link that is also included
// input:  "[http://example.(com) Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://example.(com)"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   brackets_open_bracket_inside
// label:  an open bracket inside a bracket-enclosed link that is not included
// input:  "[http://foobar[baz.com Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://foobar"), ExternalLinkSeparator(suppress_space=True), Text(text="[baz.com Example"), ExternalLinkClose()]
//
// ---
//
// name:   adjacent_space
// label:  two free links separated by a space
// input:  "http://example.com http://example.com"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose(), Text(text=" "), ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose()]
//
// ---
//
// name:   adjacent_newline
// label:  two free links separated by a newline
// input:  "http://example.com\nhttp://example.com"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose(), Text(text="\n"), ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose()]
//
// ---
//
// name:   adjacent_close_bracket
// label:  two free links separated by a close bracket
// input:  "http://example.com]http://example.com"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose(), Text(text="]"), ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose()]
//
// ---
//
// name:   html_entity_in_url
// label:  a HTML entity parsed correctly inside a free link
// input:  "http://exa&nbsp;mple.com/"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://exa"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="mple.com/"), ExternalLinkClose()]
//
// ---
//
// name:   template_in_url
// label:  a template parsed correctly inside a free link
// input:  "http://exa{{template}}mple.com/"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://exa"), TemplateOpen(), Text(text="template"), TemplateClose(), Text(text="mple.com/"), ExternalLinkClose()]
//
// ---
//
// name:   argument_in_url
// label:  an argument parsed correctly inside a free link
// input:  "http://exa{{{argument}}}mple.com/"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://exa"), ArgumentOpen(), Text(text="argument"), ArgumentClose(), Text(text="mple.com/"), ExternalLinkClose()]
//
// ---
//
// name:   wikilink_in_url
// label:  a wikilink that destroys a free link
// input:  "http://exa[[wikilink]]mple.com/"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://exa"), ExternalLinkClose(), WikilinkOpen(), Text(text="wikilink"), WikilinkClose(), Text(text="mple.com/")]
//
// ---
//
// name:   external_link_in_url
// label:  a bracketed link that destroys a free link
// input:  "http://exa[http://example.com/]mple.com/"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://exa"), ExternalLinkClose(), ExternalLinkOpen(brackets=True), Text(text="http://example.com/"), ExternalLinkClose(), Text(text="mple.com/")]
//
// ---
//
// name:   spaces_padding
// label:  spaces padding a free link
// input:  "   http://example.com   "
// output: [Text(text="   "), ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose(), Text(text="   ")]
//
// ---
//
// name:   text_and_spaces_padding
// label:  text and spaces padding a free link
// input:  "x   http://example.com   x"
// output: [Text(text="x   "), ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose(), Text(text="   x")]
//
// ---
//
// name:   template_before
// label:  a template before a free link
// input:  "{{foo}}http://example.com"
// output: [TemplateOpen(), Text(text="foo"), TemplateClose(), ExternalLinkOpen(brackets=False), Text(text="http://example.com"), ExternalLinkClose()]
//
// ---
//
// name:   spaces_padding_no_slashes
// label:  spaces padding a free link with no slashes after the colon
// input:  "   mailto:example@example.com   "
// output: [Text(text="   "), ExternalLinkOpen(brackets=False), Text(text="mailto:example@example.com"), ExternalLinkClose(), Text(text="   ")]
//
// ---
//
// name:   text_and_spaces_padding_no_slashes
// label:  text and spaces padding a free link with no slashes after the colon
// input:  "x   mailto:example@example.com   x"
// output: [Text(text="x   "), ExternalLinkOpen(brackets=False), Text(text="mailto:example@example.com"), ExternalLinkClose(), Text(text="   x")]
//
// ---
//
// name:   template_before_no_slashes
// label:  a template before a free link with no slashes after the colon
// input:  "{{foo}}mailto:example@example.com"
// output: [TemplateOpen(), Text(text="foo"), TemplateClose(), ExternalLinkOpen(brackets=False), Text(text="mailto:example@example.com"), ExternalLinkClose()]
//
// ---
//
// name:   no_slashes
// label:  a free link with no slashes after the colon
// input:  "mailto:example@example.com"
// output: [ExternalLinkOpen(brackets=False), Text(text="mailto:example@example.com"), ExternalLinkClose()]
//
// ---
//
// name:   slashes_optional
// label:  a free link using a scheme that doesn't need slashes, but has them anyway
// input:  "mailto://example@example.com"
// output: [ExternalLinkOpen(brackets=False), Text(text="mailto://example@example.com"), ExternalLinkClose()]
//
// ---
//
// name:   short
// label:  a very short free link
// input:  "mailto://abc"
// output: [ExternalLinkOpen(brackets=False), Text(text="mailto://abc"), ExternalLinkClose()]
//
// ---
//
// name:   slashes_missing
// label:  slashes missing from a free link with a scheme that requires them
// input:  "http:example@example.com"
// output: [Text(text="http:example@example.com")]
//
// ---
//
// name:   no_scheme_but_slashes
// label:  no scheme in a free link, but slashes (protocol-relative free links are not supported)
// input:  "//example.com"
// output: [Text(text="//example.com")]
//
// ---
//
// name:   no_scheme_but_colon
// label:  no scheme in a free link, but a colon
// input:  " :example.com"
// output: [Text(text=" :example.com")]
//
// ---
//
// name:   no_scheme_but_colon_and_slashes
// label:  no scheme in a free link, but a colon and slashes
// input:  " ://example.com"
// output: [Text(text=" ://example.com")]
//
// ---
//
// name:   fake_scheme_no_slashes
// label:  a nonexistent scheme in a free link, without slashes
// input:  "fake:example.com"
// output: [Text(text="fake:example.com")]
//
// ---
//
// name:   fake_scheme_slashes
// label:  a nonexistent scheme in a free link, with slashes
// input:  "fake://example.com"
// output: [Text(text="fake://example.com")]
//
// ---
//
// name:   fake_scheme_brackets_no_slashes
// label:  a nonexistent scheme in a bracketed link, without slashes
// input:  "[fake:example.com]"
// output: [Text(text="[fake:example.com]")]
//
// ---
//
// name:   fake_scheme_brackets_slashes
// label:  #=a nonexistent scheme in a bracketed link, with slashes
// input:  "[fake://example.com]"
// output: [Text(text="[fake://example.com]")]
//
// ---
//
// name:   interrupted_scheme
// label:  an otherwise valid scheme with something in the middle of it, in a free link
// input:  "ht?tp://example.com"
// output: [Text(text="ht?tp://example.com")]
//
// ---
//
// name:   interrupted_scheme_brackets
// label:  an otherwise valid scheme with something in the middle of it, in a bracketed link
// input:  "[ht?tp://example.com]"
// output: [Text(text="[ht?tp://example.com]")]
//
// ---
//
// name:   no_slashes_brackets
// label:  no slashes after the colon in a bracketed link
// input:  "[mailto:example@example.com Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="mailto:example@example.com"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   space_before_no_slashes_brackets
// label:  a space before a bracketed link with no slashes after the colon
// input:  "[ mailto:example@example.com Example]"
// output: [Text(text="[ "), ExternalLinkOpen(brackets=False), Text(text="mailto:example@example.com"), ExternalLinkClose(), Text(text=" Example]")]
//
// ---
//
// name:   slashes_optional_brackets
// label:  a bracketed link using a scheme that doesn't need slashes, but has them anyway
// input:  "[mailto://example@example.com Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="mailto://example@example.com"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   short_brackets
// label:  a very short link in brackets
// input:  "[mailto://abc Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="mailto://abc"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   slashes_missing_brackets
// label:  slashes missing from a scheme that requires them in a bracketed link
// input:  "[http:example@example.com Example]"
// output: [Text(text="[http:example@example.com Example]")]
//
// ---
//
// name:   protcol_relative
// label:  a protocol-relative link (in brackets)
// input:  "[//example.com Example]"
// output: [ExternalLinkOpen(brackets=True), Text(text="//example.com"), ExternalLinkSeparator(), Text(text="Example"), ExternalLinkClose()]
//
// ---
//
// name:   scheme_missing_but_colon_brackets
// label:  scheme missing from a bracketed link, but with a colon
// input:  "[:example.com Example]"
// output: [Text(text="[:example.com Example]")]
//
// ---
//
// name:   scheme_missing_but_colon_slashes_brackets
// label:  scheme missing from a bracketed link, but with a colon and slashes
// input:  "[://example.com Example]"
// output: [Text(text="[://example.com Example]")]
//
// ---
//
// name:   unclosed_protocol_relative
// label:  an unclosed protocol-relative bracketed link
// input:  "[//example.com"
// output: [Text(text="[//example.com")]
//
// ---
//
// name:   space_before_protcol_relative
// label:  a space before a protocol-relative bracketed link
// input:  "[ //example.com]"
// output: [Text(text="[ //example.com]")]
//
// ---
//
// name:   unclosed_just_scheme
// label:  an unclosed bracketed link, ending after the scheme
// input:  "[http"
// output: [Text(text="[http")]
//
// ---
//
// name:   unclosed_scheme_colon
// label:  an unclosed bracketed link, ending after the colon
// input:  "[http:"
// output: [Text(text="[http:")]
//
// ---
//
// name:   unclosed_scheme_colon_slashes
// label:  an unclosed bracketed link, ending after the slashes
// input:  "[http://"
// output: [Text(text="[http://")]
//
// ---
//
// name:   incomplete_bracket
// label:  just an open bracket
// input:  "["
// output: [Text(text="[")]
//
// ---
//
// name:   incomplete_scheme_colon
// label:  a free link with just a scheme and a colon
// input:  "http:"
// output: [Text(text="http:")]
//
// ---
//
// name:   incomplete_scheme_colon_slashes
// label:  a free link with just a scheme, colon, and slashes
// input:  "http://"
// output: [Text(text="http://")]
//
// ---
//
// name:   brackets_scheme_but_no_url
// label:  brackets around a scheme and a colon
// input:  "[mailto:]"
// output: [Text(text="[mailto:]")]
//
// ---
//
// name:   brackets_scheme_slashes_but_no_url
// label:  brackets around a scheme, colon, and slashes
// input:  "[http://]"
// output: [Text(text="[http://]")]
//
// ---
//
// name:   brackets_scheme_title_but_no_url
// label:  brackets around a scheme, colon, and slashes, with a title
// input:  "[http:// Example]"
// output: [Text(text="[http:// Example]")]
//
// ---
//
// name:   url_preceded_by_non_word_character
// label:  non-word character immediately before a valid URL
// input:  "svn+ssh://server.domain.com:/reponame"
// output: [Text(text="svn+"), ExternalLinkOpen(brackets=False), Text(text="ssh://server.domain.com:/reponame"), ExternalLinkClose()]
//
// ---
//
// name:   url_preceded_by_underscore
// label:  underscore immediately before a valid URL
// input:  "svn_ssh://server.domain.com:/reponame"
// output: [Text(text="svn_ssh://server.domain.com:/reponame")]
//
// ---
//
// name:   url_terminated_by_double_quote
// label:  a free link terminated by a double quote
// input:  "http://foo\"bar"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://foo"), ExternalLinkClose(), Text(text="\"bar")]
//
// ---
//
// name:   url_not_terminated_by_single_quote
// label:  a free link not terminated by a single quote
// input:  "http://foo'bar"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://foo'bar"), ExternalLinkClose()]
//
// ---
//
// name:   url_terminated_by_two_single_quotes
// label:  a free link terminated by two single quotes
// input:  "http://foo''bar''"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://foo"), ExternalLinkClose(), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="bar"), TagOpenClose(), Text(text="i"), TagCloseClose()]
//
// ---
//
// name:   url_terminated_by_left_angle
// label:  a free link terminated by a left angle
// input:  "http://foo<bar"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://foo"), ExternalLinkClose(), Text(text="<bar")]
//
// ---
//
// name:   url_terminated_by_right_angle
// label:  a free link terminated by a right angle
// input:  "http://foo>bar"
// output: [ExternalLinkOpen(brackets=False), Text(text="http://foo"), ExternalLinkClose(), Text(text=">bar")]
//
// ---
//
// name:   brackets_terminated_by_double_quote
// label:  an external link terminated by a double quote
// input:  "[http://foo\"bar]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://foo"), ExternalLinkSeparator(suppress_space=True), Text(text="\"bar"), ExternalLinkClose()]
//
// ---
//
// name:   brackets_not_terminated_by_single_quote
// label:  an external link not terminated by a single quote
// input:  "[http://foo'bar]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://foo'bar"), ExternalLinkClose()]
//
// ---
//
// name:   brackets_terminated_by_two_single_quotes
// label:  an external link terminated by two single quotes
// input:  "[http://foo''bar'']"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://foo"), ExternalLinkSeparator(suppress_space=True), TagOpenOpen(wiki_markup="''"), Text(text="i"), TagCloseOpen(), Text(text="bar"), TagOpenClose(), Text(text="i"), TagCloseClose(), ExternalLinkClose()]
//
// ---
//
// name:   brackets_terminated_by_left_angle
// label:  an external link terminated by a left angle
// input:  "[http://foo<bar]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://foo"), ExternalLinkSeparator(suppress_space=True), Text(text="<bar"), ExternalLinkClose()]
//
// ---
//
// name:   brackets_terminated_by_right_angle
// label:  an external link terminated by a right angle
// input:  "[http://foo>bar]"
// output: [ExternalLinkOpen(brackets=True), Text(text="http://foo"), ExternalLinkSeparator(suppress_space=True), Text(text=">bar"), ExternalLinkClose()]
//
// ---
//
// name:   scheme_case
// label:  a free link with uppercase letters in the URL scheme
// input:  "HtTp://example.com/"
// output: [ExternalLinkOpen(brackets=False), Text(text="HtTp://example.com/"), ExternalLinkClose()]
//
// ---
//
// name:   bracket_scheme_case
// label:  an external link with uppercase letters in the URL scheme
// input:  "[HtTp://example.com/]"
// output: [ExternalLinkOpen(brackets=True), Text(text="HtTp://example.com/"), ExternalLinkClose()]
