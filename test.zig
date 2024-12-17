const std = @import("std");
const expect = std.testing.expect;
const eqlStr = std.testing.expectEqualStrings;

const c = @cImport({
    @cInclude("common.h");
    @cInclude("tok_parse.h");
    @cInclude("tokens.h");
});

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

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    return tokenlist.*;
}

fn cText(txt: [*:0]const u8) [*c]u8 {
    return @constCast(@ptrCast(txt));
}

fn expectTokensEql(expected: []const c.Token, actual: c.TokenList) !void {
    try expect(expected.len == actual.len);
    for (expected, 0..) |expected_token, i| {
        const actual_token = actual.tokens[i];
        try expect(expected_token.type == actual_token.type);
        if (expected_token.type == c.Text) {
            try eqlStr(textFromTextTok(expected_token), textFromTextTok(actual_token));
        }
    }
}

// **************
// Text / Unicode
// **************

test "sanity check for basic text parsing, no gimmicks" {
    const txt = "foobar";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("foobar", tokenlist.tokens[0]);
}

test "slightly more complex text parsing, with newlines" {
    const txt = "This is a line of text.\nThis is another line of text.\nThis is another.";

    const tokenlist = tokenize(txt);

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is a line of text.\nThis is another line of text.\nThis is another.", tokenlist.tokens[0]);
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

    const tokenlist = tokenize(txt);

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

        const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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
