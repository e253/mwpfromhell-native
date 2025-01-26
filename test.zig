const std = @import("std");
const expect = std.testing.expect;
const eqlStr = std.testing.expectEqualStrings;

const c = @cImport({
    @cInclude("common.h");
    @cInclude("tok_parse.h");
    @cInclude("tokens.h");
});

const Arena = c.memory_arena_t;

fn printTokens(tokenlist: c.TokenList) void {
    var i: u32 = 0;
    while (i < tokenlist.len) : (i += 1) {
        const token = tokenlist.tokens[i];
        if (token.type == c.Text) {
            std.debug.print("Text(\"{s}\")", .{@as([*c]const u8, @ptrCast(token.ctx.data))});
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

test "italics with a lot in them" {
    //const txt = "''this is a&nbsp;test of [[Italic text|italics]] with {{plenty|of|stuff}}";

    //var tokenizer = std.mem.zeroes(c.Tokenizer);
    //tokenizer.text.data = @constCast(txt.ptr);
    //tokenizer.text.length = txt.len;

    //const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));
    //_ = tokenlist;

    return error.SkipZigTest;
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
    //const txt = "''this is 'not' the en'd'<nowiki>''</nowiki>";
    //const tokenlist = tokenize(txt);
    return error.SkipZigTest;
}

test "italics that start outside a link and end inside it" {
    //const txt = "''foo[[bar|baz'']]spam";
    return error.SkipZigTest;
}

test "bold with a lot in it" {
    //const txt = "'''this is a&nbsp;test of [[Bold text|bold]] with {{plenty|of|stuff}}'''";
    return error.SkipZigTest;
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
    //const txt = "'''this is 'not' the en''d'<nowiki>'''</nowiki>";
    //const tokenlist = tokenize(txt);
    return error.SkipZigTest;
}

test "bold that start outside a link and end inside it" {
    //const txt = "'''foo[[bar|baz''']]spam";
    return error.SkipZigTest;
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
    const txt = "''italics'''both'''''";
    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 6);
    try expect(tokenlist.tokens[0].type == c.ItalicOpen);
    try expectTextTokEql("italics", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.BoldOpen);
    try expectTextTokEql("both", tokenlist.tokens[3]);
    try expect(tokenlist.tokens[4].type == c.BoldClose);
    try expect(tokenlist.tokens[5].type == c.ItalicClose);
}

test "text that starts italic, then is bold" {
    const txt = "none''italics'''''bold'''none";
    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 8);
    try expectTextTokEql("none", tokenlist.tokens[0]);
    try expect(tokenlist.tokens[1].type == c.ItalicOpen);
    try expectTextTokEql("italics", tokenlist.tokens[2]);
    try expect(tokenlist.tokens[3].type == c.ItalicClose);
    try expect(tokenlist.tokens[4].type == c.BoldOpen);
    try expectTextTokEql("bold", tokenlist.tokens[5]);
    try expect(tokenlist.tokens[6].type == c.BoldClose);
    try expectTextTokEql("none", tokenlist.tokens[7]);
}

test "text that starts bold, then is italic" {
    const txt = "none'''bold'''''italics''none";
    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 8);
    try expectTextTokEql("none", tokenlist.tokens[0]);
    try expect(tokenlist.tokens[1].type == c.BoldOpen);
    try expectTextTokEql("bold", tokenlist.tokens[2]);
    try expect(tokenlist.tokens[3].type == c.BoldClose);
    try expect(tokenlist.tokens[4].type == c.ItalicOpen);
    try expectTextTokEql("italics", tokenlist.tokens[5]);
    try expect(tokenlist.tokens[6].type == c.ItalicClose);
    try expectTextTokEql("none", tokenlist.tokens[7]);
}

test "five ticks to open, three to close (bold)" {
    const txt = "'''''foobar'''";
    const tokenlist = tokenize(txt);

    const tokenarr = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("''") } },
        .{ .type = c.BoldOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foobar") } },
        .{ .type = c.BoldClose },
    };

    try expectTokensEql(&tokenarr, tokenlist);
}

test "five ticks to open, two to close (bold)" {
    const txt = "'''''foobar''";
    const tokenlist = tokenize(txt);

    const tokenarr = [_]c.Token{
        .{ .type = c.Text, .ctx = .{ .data = cText("'''") } },
        .{ .type = c.ItalicOpen },
        .{ .type = c.Text, .ctx = .{ .data = cText("foobar") } },
        .{ .type = c.ItalicClose },
    };

    try expectTokensEql(&tokenarr, tokenlist);
}

test "four ticks" {
    const actual = tokenize("foo ''''bar'''' baz");

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
    const actual = tokenize("foo ''''bar'' baz");

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
    const actual = tokenize("foo ''bar''' baz''");

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
    const actual = tokenize("foo ''bar'''' baz''''");

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
    const actual = tokenize("'''''''seven'''''''");

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
    const actual = tokenize("'''''testing");

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
    //const actual = tokenize("* this is a&nbsp;test of an [[Unordered list|ul]] with {{plenty|of|stuff}}");

    //const expected = [_]c.Token{
    //    .{ .type = c.UnorderedListItem },
    //    .{ .type = c.Text, .ctx = .{ .data = cText(" this is a") } },
    //    .{ .type = c.HTMLEntityStart },
    //    .{ .type = c.Text, .ctx = .{ .data = cText("") } },
    //};

    //try expectTokensEql(&expected, actual);
    return error.SkipZigTest;
}

// name:   ul_multiline_template
// label:  ul with a template that spans multiple lines
// input:  "* this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
test "ul with a template that spans multiple lines" {
    const actual = tokenize("* this has a template with a {{line|\nbreak}}\nthis is not part of the list");

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
    const actual = tokenize("a\n*b\n*c\nd\n*e\nf");

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
    // var a: Arena = std.mem.zeroes(Arena);
    // try std.testing.expect(c.arena_init(&a) == 0);
    // defer c.arena_clear(&a);

    // const actual = tokenize_arena(&a, "# this is a&nbsp;test of an [[Ordered list|ol]] with {{plenty|of|stuff}}");

    // const expected = [_]c.Token{
    //     .{ .type = c.UnorderedListItem },
    //     .{ .type = c.UnorderedListItem },
    //     .{ .type = c.Text, .ctx = .{ .data = cText("f*oobar") } },
    // };

    // try expectTokensEql(&expected, actual);
    return error.SkipZigTest;
}

// name:   ol_multiline_template
// label:  ol with a template that spans moltiple lines
// input:  "# this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
//
// ---
//
// name:   ol_adjacent
// label:  moltiple adjacent ols
// input:  "a\n#b\n#c\nd\n#e\nf"
// output: [Text(text="a\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="c\nd\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf")]
//
// ---
//
// name:   ol_depths
// label:  moltiple adjacent ols, with differing depths
// input:  "#a\n##b\n###c\n########d\n##e\nf\n###g"
// output: [TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="g")]
//
// ---
//
// name:   ol_space_before
// label:  ols with space before them
// input:  "foo    #bar\n #baz\n#buzz"
// output: [Text(text="foo    #bar\n #baz\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="buzz")]
//
// ---
//
// name:   ol_interruption
// label:  high-depth ol with something blocking it
// input:  "##f#oobar"
// output: [TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="f#oobar")]
//
// ---
//
// name:   ul_ol_mix
// label:  a mix of adjacent uls and ols
// input:  "*a\n*#b\n*##c\n*##*#*#*d\n*#e\nf\n##*g"
// output: [TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="g")]
//
// ---
//
// name:   complex_dt
// label:  dt with a lot in it
// input:  "; this is a&nbsp;test of an [[description term|dt]] with {{plenty|of|stuff}}"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text=" this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of an "), WikilinkOpen(), Text(text="description term"), WikilinkSeparator(), Text(text="dt"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose()]
//
// ---
//
// name:   dt_multiline_template
// label:  dt with a template that spans mdttiple lines
// input:  "; this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
//
// ---
//
// name:   dt_adjacent
// label:  mdttiple adjacent dts
// input:  "a\n;b\n;c\nd\n;e\nf"
// output: [Text(text="a\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="c\nd\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="e\nf")]
//
// ---
//
// name:   dt_depths
// label:  mdttiple adjacent dts, with differing depths
// input:  ";a\n;;b\n;;;c\n;;;;;;;;d\n;;e\nf\n;;;g"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="g")]
//
// ---
//
// name:   dt_space_before
// label:  dts with space before them
// input:  "foo    ;bar\n ;baz\n;buzz"
// output: [Text(text="foo    ;bar\n ;baz\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="buzz")]
//
// ---
//
// name:   dt_interruption
// label:  high-depth dt with something blocking it
// input:  ";;f;oobar"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="f;oobar")]
//
// ---
//
// name:   complex_dd
// label:  dd with a lot in it
// input:  ": this is a&nbsp;test of an [[description item|dd]] with {{plenty|of|stuff}}"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text=" this is a"), HTMLEntityStart(), Text(text="nbsp"), HTMLEntityEnd(), Text(text="test of an "), WikilinkOpen(), Text(text="description item"), WikilinkSeparator(), Text(text="dd"), WikilinkClose(), Text(text=" with "), TemplateOpen(), Text(text="plenty"), TemplateParamSeparator(), Text(text="of"), TemplateParamSeparator(), Text(text="stuff"), TemplateClose()]
//
// ---
//
// name:   dd_multiline_template
// label:  dd with a template that spans mddtiple lines
// input:  ": this has a template with a {{line|\nbreak}}\nthis is not part of the list"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text=" this has a template with a "), TemplateOpen(), Text(text="line"), TemplateParamSeparator(), Text(text="\nbreak"), TemplateClose(), Text(text="\nthis is not part of the list")]
//
// ---
//
// name:   dd_adjacent
// label:  mddtiple adjacent dds
// input:  "a\n:b\n:c\nd\n:e\nf"
// output: [Text(text="a\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="c\nd\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="e\nf")]
//
// ---
//
// name:   dd_depths
// label:  mddtiple adjacent dds, with differing depths
// input:  ":a\n::b\n:::c\n::::::::d\n::e\nf\n:::g"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="g")]
//
// ---
//
// name:   dd_space_before
// label:  dds with space before them
// input:  "foo    :bar\n :baz\n:buzz"
// output: [Text(text="foo    :bar\n :baz\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="buzz")]
//
// ---
//
// name:   dd_interruption
// label:  high-depth dd with something blocking it
// input:  "::f:oobar"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="f:oobar")]
//
// ---
//
// name:   dt_dd_mix
// label:  a mix of adjacent dts and dds
// input:  ";a\n;:b\n;::c\n;::;:;:;d\n;:e\nf\n::;g"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="a\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="b\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="c\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="d\n"), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="e\nf\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="g")]
//
// ---
//
// name:   dt_dd_mix2
// label:  the correct usage of a dt/dd unit, as in a dl
// input:  ";foo:bar:baz"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="foo"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="bar:baz")]
//
// ---
//
// name:   dt_dd_mix3
// label:  another example of correct (but strange) dt/dd usage
// input:  ":;;::foo:bar:baz"
// output: [TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="foo"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="bar:baz")]
//
// ---
//
// name:   dt_dd_mix4
// label:  another example of correct dt/dd usage, with a trigger for a specific parse route
// input:  ";foo]:bar"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="foo]"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="bar")]
//
// ---
//
// name:   ul_ol_dt_dd_mix
// label:  an assortment of uls, ols, dds, and dts
// input:  ";:#*foo\n:#*;foo\n#*;:foo\n*;:#foo"
// output: [TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), Text(text="foo\n"), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), Text(text="foo\n"), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), Text(text="foo\n"), TagOpenOpen(wiki_markup="*"), Text(text="li"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=";"), Text(text="dt"), TagCloseSelfclose(), TagOpenOpen(wiki_markup=":"), Text(text="dd"), TagCloseSelfclose(), TagOpenOpen(wiki_markup="#"), Text(text="li"), TagCloseSelfclose(), Text(text="foo")]
//
// ---
//
// name:   hr_text_before
// label:  text before an otherwise-valid hr
// input:  "foo----"
// output: [Text(text="foo----")]
//
// ---
//
// name:   hr_text_after
// label:  text after a valid hr
// input:  "----bar"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="bar")]
//
// ---
//
// name:   hr_text_before_after
// label:  text at both ends of an otherwise-valid hr
// input:  "foo----bar"
// output: [Text(text="foo----bar")]
//
// ---
//
// name:   hr_newlines
// label:  newlines surrounding a valid hr
// input:  "foo\n----\nbar"
// output: [Text(text="foo\n"), TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="\nbar")]
//
// ---
//
// name:   hr_adjacent
// label:  two adjacent hrs
// input:  "----\n----"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="\n"), TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose()]
//
// ---
//
// name:   hr_adjacent_space
// label:  two adjacent hrs, with a space before the second one, making it invalid
// input:  "----\n ----"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="\n ----")]
//
// ---
//
// name:   hr_short
// label:  an invalid three-hyphen-long hr
// input:  "---"
// output: [Text(text="---")]
//
// ---
//
// name:   hr_long
// label:  a very long, valid hr
// input:  "------------------------------------------"
// output: [TagOpenOpen(wiki_markup="------------------------------------------"), Text(text="hr"), TagCloseSelfclose()]
//
// ---
//
// name:   hr_interruption_short
// label:  a hr that is interrupted, making it invalid
// input:  "---x-"
// output: [Text(text="---x-")]
//
// ---
//
// name:   hr_interruption_long
// label:  a hr that is interrupted, but the first part remains valid because it is long enough
// input:  "----x--"
// output: [TagOpenOpen(wiki_markup="----"), Text(text="hr"), TagCloseSelfclose(), Text(text="x--")]
//
// ---
//
// name:   nowiki_cancel
// label:  a nowiki tag before a list causes it to not be parsed
// input:  "<nowiki />* Unordered list"
// output: [TagOpenOpen(), Text(text="nowiki"), TagCloseSelfclose(padding=" "), Text(text="* Unordered list")]
