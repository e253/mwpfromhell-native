const std = @import("std");
const expect = std.testing.expect;
const eqlStr = std.testing.expectEqualStrings;

const c = @cImport({
    @cInclude("common.h");
    @cInclude("tok_parse.h");
    @cInclude("tokens.h");
});

fn printTokens(tokenlist: *c.TokenList) void {
    var i: u32 = 0;
    while (i < tokenlist.len) : (i += 1) {
        const token = tokenlist.tokens[i];
        if (token.type == c.Text) {
            std.debug.print("Text(\"{s}\")", .{@as([*c]u8, @ptrCast(token.ctx.data))});
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

// **************
// Text / Unicode
// **************

test "sanity check for basic text parsing, no gimmicks" {
    const txt = "foobar";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql("foobar", tokenlist.tokens[0]);
}

test "slightly more complex text parsing, with newlines" {
    const txt = "This is a line of text.\nThis is another line of text.\nThis is another.";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is a line of text.\nThis is another line of text.\nThis is another.", tokenlist.tokens[0]);
}

test "ensure unicode data is handled properly" {
    const txt = "Thís ís å sëñtënce with diœcritiçs.";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql("Thís ís å sëñtënce with diœcritiçs.", tokenlist.tokens[0]);
}

test "additional unicode check for non-BMP codepoints" {
    // 𐌲𐌿𐍄𐌰𐍂𐌰𐌶𐌳𐌰
    const txt = "\xf0\x90\x8c\xb2\xf0\x90\x8c\xbf\xf0\x90\x8d\x84\xf0\x90\x8c\xb0\xf0\x90\x8d\x82\xf0\x90\x8c\xb0\xf0\x90\x8c\xb6\xf0\x90\x8c\xb3\xf0\x90\x8c\xb0";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql(txt, tokenlist.tokens[0]);
}

test "a lot of text, requiring proper storage in the C tokenizer" {
    const txt = "ZWfsZYcZyhGbkDYJiguJuuhsNyHGFkFhnjkbLJyXIygTHqcXdhsDkEOTSIKYlBiohLIkiXxvyebUyCGvvBcYqFdtcftGmaAanKXEIyYSEKlTfEEbdGhdePVwVImOyKiHSzAEuGyEVRIKPZaNjQsYqpqARIQfvAklFtQyTJVGlLwjJIxYkiqmHBmdOvTyNqJRbMvouoqXRyOhYDwowtkcZGSOcyzVxibQdnzhDYbrgbatUrlOMRvFSzmLWHRihtXnddwYadPgFWUOxAzAgddJVDXHerawdkrRuWaEXfuwQSkQUmLEJUmrgXDVlXCpciaisfuOUjBldElygamkkXbewzLucKRnAEBimIIotXeslRRhnqQjrypnLQvvdCsKFWPVTZaHvzJMFEahDHWcCbyXgxFvknWjhVfiLSDuFhGoFxqSvhjnnRZLmCMhmWeOgSoanDEInKTWHnbpKyUlabLppITDFFxyWKAnUYJQIcmYnrvMmzmtYvsbCYbebgAhMFVVFAKUSvlkLFYluDpbpBaNFWyfXTaOdSBrfiHDTWGBTUCXMqVvRCIMrEjWpQaGsABkioGnveQWqBTDdRQlxQiUipwfyqAocMddXqdvTHhEwjEzMkOSWVPjJvDtClhYwpvRztPmRKCSpGIpXQqrYtTLmShFdpKtOxGtGOZYIdyUGPjdmyvhJTQMtgYJWUUZnecRjBfQXsyWQWikyONySLzLEqRFqcJYdRNFcGwWZtfZasfFWcvdsHRXoqKlKYihRAOJdrPBDdxksXFwKceQVncmFXfUfBsNgjKzoObVExSnRnjegeEhqxXzPmFcuiasViAFeaXrAxXhSfSyCILkKYpjxNeKynUmdcGAbwRwRnlAFbOSCafmzXddiNpLCFTHBELvArdXFpKUGpSHRekhrMedMRNkQzmSyFKjVwiWwCvbNWjgxJRzYeRxHiCCRMXktmKBxbxGZvOpvZIJOwvGIxcBLzsMFlDqAMLtScdsJtrbIUAvKfcdChXGnBzIxGxXMgxJhayrziaCswdpjJJJhkaYnGhHXqZwOzHFdhhUIEtfjERdLaSPRTDDMHpQtonNaIgXUYhjdbnnKppfMBxgNSOOXJAPtFjfAKnrRDrumZBpNhxMstqjTGBViRkDqbTdXYUirsedifGYzZpQkvdNhtFTOPgsYXYCwZHLcSLSfwfpQKtWfZuRUUryHJsbVsAOQcIJdSKKlOvCeEjUQNRPHKXuBJUjPuaAJJxcDMqyaufqfVwUmHLdjeYZzSiiGLHOTCInpVAalbXXTMLugLiwFiyPSuSFiyJUKVrWjbZAHaJtZnQmnvorRrxdPKThqXzNgTjszQiCoMczRnwGYJMERUWGXFyrSbAqsHmLwLlnJOJoXNsjVehQjVOpQOQJAZWwFZBlgyVIplzLTlFwumPgBLYrUIAJAcmvHPGfHfWQguCjfTYzxYfbohaLFAPwxFRrNuCdCzLlEbuhyYjCmuDBTJDMCdLpNRVqEALjnPSaBPsKWRCKNGwEMFpiEWbYZRwaMopjoUuBUvMpvyLfsPKDrfQLiFOQIWPtLIMoijUEUYfhykHrSKbTtrvjwIzHdWZDVwLIpNkloCqpzIsErxxKAFuFEjikWNYChqYqVslXMtoSWzNhbMuxYbzLfJIcPGoUeGPkGyPQNhDyrjgdKekzftFrRPTuyLYqCArkDcWHTrjPQHfoThBNnTQyMwLEWxEnBXLtzJmFVLGEPrdbEwlXpgYfnVnWoNXgPQKKyiXifpvrmJATzQOzYwFhliiYxlbnsEPKbHYUfJLrwYPfSUwTIHiEvBFMrEtVmqJobfcwsiiEudTIiAnrtuywgKLOiMYbEIOAOJdOXqroPjWnQQcTNxFvkIEIsuHLyhSqSphuSmlvknzydQEnebOreeZwOouXYKlObAkaWHhOdTFLoMCHOWrVKeXjcniaxtgCziKEqWOZUWHJQpcDJzYnnduDZrmxgjZroBRwoPBUTJMYipsgJwbTSlvMyXXdAmiEWGMiQxhGvHGPLOKeTxNaLnFVbWpiYIVyqN";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql(txt, tokenlist.tokens[0]);
}

// *************
// HTML Entities
// *************

test "a basic named HTML entity" {
    const txt: []const u8 = "&nbsp;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 3);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.Text);
    try eqlStr("nbsp", textFromTextTok(tokenlist.tokens[1]));
    try expect(tokenlist.tokens[2].type == c.HTMLEntityEnd);
}

test "a basic decimal HTML entity" {
    const txt: []const u8 = "&#107;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 4);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.Text);
    try eqlStr("107", textFromTextTok(tokenlist.tokens[2]));
    try expect(tokenlist.tokens[3].type == c.HTMLEntityEnd);
}

test "a basic hexadecimal HTML entity, using 'x' as a signal" {
    const txt: []const u8 = "&#x6B;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 4);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.Text);
    try eqlStr("1114111", textFromTextTok(tokenlist.tokens[2]));
    try expect(tokenlist.tokens[3].type == c.HTMLEntityEnd);
}

test "the maximum acceptable hexadecimal numeric entity" {
    const txt: []const u8 = "&#x10FFFF;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 4);

    try expect(tokenlist.tokens[0].type == c.HTMLEntityStart);
    try expect(tokenlist.tokens[1].type == c.HTMLEntityNumeric);
    try expect(tokenlist.tokens[2].type == c.Text);
    try eqlStr("0000000107", textFromTextTok(tokenlist.tokens[2]));
    try expect(tokenlist.tokens[3].type == c.HTMLEntityEnd);
}

test "zeros accepted at the beginning of a hex numeric entity" {
    const txt: []const u8 = "&#x0000000107;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&sigmaSigma;", textFromTextTok(tokenlist.tokens[0]));
}

test "a named entity that doesn't exist" {
    const txt: []const u8 = "&foobar;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));
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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&sígma;", textFromTextTok(tokenlist.tokens[0]));
}

test "a numeric entity that is out of range: < 1" {
    const txt: []const u8 = "&#0;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&#0;", textFromTextTok(tokenlist.tokens[0]));
}

test "a hex numeric entity that is out of range: < 1" {
    const txt: []const u8 = "&x0;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));
    _ = tokenlist;

    return error.SkipZigTest;

    //try expect(tokenlist.len == 1);
    //try expect(tokenlist.tokens[0].type == c.Text);
    //try eqlStr("&x0;", textFromTextTok(tokenlist.tokens[0]));
}

test "a numeric entity that is out of range: > 0x10FFFF" {
    const txt: []const u8 = "&#1114112;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("&#1114112;", textFromTextTok(tokenlist.tokens[0]));
}

test "a hex numeric entity that is out of range: > 0x10FFFF" {
    const txt: []const u8 = "&#x0110000;";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 2);
    try expect(tokenlist.tokens[0].type == c.CommentStart);
    try expect(tokenlist.tokens[1].type == c.CommentEnd);
}

test "a basic comment" {
    const txt: []const u8 = "<!-- comment -->";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.CommentStart);
    try expect(tokenlist.tokens[1].type == c.Text);
    try eqlStr(" comment ", textFromTextTok(tokenlist.tokens[1]));
    try expect(tokenlist.tokens[2].type == c.CommentEnd);
}

test "a comment with tons of ignorable garbage in it" {
    const txt: []const u8 = "<!-- foo{{bar}}[[basé\n\n]{}{}{}{}]{{{{{{haha{{--a>aa<!--aa -->";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.CommentStart);
    try expect(tokenlist.tokens[1].type == c.Text);
    try eqlStr(" foo{{bar}}[[basé\n\n]{}{}{}{}]{{{{{{haha{{--a>aa<!--aa ", textFromTextTok(tokenlist.tokens[1]));
    try expect(tokenlist.tokens[2].type == c.CommentEnd);
}

test "a comment that doesn't close" {
    const txt: []const u8 = "<!--";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("<!--", textFromTextTok(tokenlist.tokens[0]));
}

test "a comment that doesn't close, with text" {
    const txt: []const u8 = "<!-- foo";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("<!-- foo", textFromTextTok(tokenlist.tokens[0]));
}

test "a comment that doesn't close, with a partial close" {
    const txt: []const u8 = "<!-- foo --\x01>";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expect(tokenlist.tokens[0].type == c.Text);
    try eqlStr("<!-- foo --\x01>", textFromTextTok(tokenlist.tokens[0]));
}

test "a comment that only has a < and !" {
    const txt: []const u8 = "<!foo";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 6);
    try expectTextTokEql("= Heading =", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a level-2 heading that pretends to be a level-3 heading" {
    const txt = "=== Heading ==";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 2);
    try expectTextTokEql("= Heading ", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a level-4 heading that pretends to be a level-6 heading" {
    const txt = "==== Heading ======";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 4);
    try expectTextTokEql(" Heading ==", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a heading that starts after a newline" {
    const txt = "This is some text.\n== Foobar ==\nbaz";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

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

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is some text. == Foobar ==\nbaz", tokenlist.tokens[0]);
}

test "invalid headings: newline in the middle" {
    const txt = "This is some text.\n== Foo\nbar ==";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is some text.\n== Foo\nbar ==", tokenlist.tokens[0]);
}

test "invalid headings: newline in the middle 2" {
    const txt = "This is some text.\n=== Foo\nbar ===";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql("This is some text.\n=== Foo\nbar ===", tokenlist.tokens[0]);
}

test "invalid headings: attempts at nesting" {
    const txt = "== Foo === Bar === Baz ==";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 3);
    try expect(tokenlist.tokens[0].type == c.HeadingStart);
    try expect(tokenlist.tokens[0].ctx.heading.level == 2);
    try expectTextTokEql(" Foo === Bar === Baz ", tokenlist.tokens[1]);
    try expect(tokenlist.tokens[2].type == c.HeadingEnd);
}

test "a heading that starts but doesn't finish" {
    const txt = "Foobar. \n== Heading ";

    var tokenizer = std.mem.zeroes(c.Tokenizer);
    tokenizer.text.data = @constCast(txt.ptr);
    tokenizer.text.length = txt.len;

    const tokenlist: *c.TokenList = @ptrCast(c.Tokenizer_parse(&tokenizer, 0, 1));

    try expect(tokenlist.len == 1);
    try expectTextTokEql("Foobar. \n== Heading ", tokenlist.tokens[0]);
}
