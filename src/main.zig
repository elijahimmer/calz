pub fn main() !void {
    const stdout_file = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout_file.writer());
    defer bw.flush() catch {};
    const stdout = bw.writer();

    const stdin_file = std.io.getStdIn();
    //var br = std.io.bufferedReader(stdin_file.reader());
    //const stdin = br.reader();

    // set terminal mode
    var term_manager = try TermManager.init(stdout_file, stdin_file);
    defer term_manager.deinit() catch {};

    global_term_manager = &term_manager;

    try term_manager.alternateBufferEnter();
    try term_manager.modeSetRaw();
    try term_manager.bracketedPasteSet();
    try term_manager.progressiveSet(.{
        .disambiguate = true,
        .event_types = true,
        .alternate_keys = true,
        .keys_as_escape_codes = true,
        .associated_text = true,
    });
    try term_manager.sendCommand(.home, .{});

    while (true) {
        const input = try Input.parse.readOneInput(stdin_file.reader());

        try input.print(stdout);

        switch (input.input_type) {
            .release => continue,
            else => {},
        }

        try stdout.print("\t{s}   \tchord: '", .{@tagName(input.input_type)});

        for (input.chord.constSlice()) |c| try print_ascii(stdout, c);

        try stdout.writeAll("'\r\n");
        try bw.flush();

        if (@as(Input.KeyCodeTag, input.key_code) == .text and input.key_code.text == 'c' and input.modifiers.onlyActive(.ctrl)) break;
        //// test panic
        //if (@as(Input.KeyCodeTag, input.key_code) == .text and input.key_code.text == 'z' and input.modifiers.onlyActive(.ctrl)) @panic("test panic");
    }
}

pub fn print_ascii(writer: anytype, char: u8) @TypeOf(writer).Error!void {
    switch (char) {
        // 1 => "^A", 2 => "^B", 3 => "^C", etc
        0...31 => try writer.print("^{c}", .{'A' - 1 + char}),
        127 => try writer.writeAll("Backspace"),
        else => try writer.print("{c}", .{char}),
    }
}

pub fn panic(message: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (global_term_manager) |m| m.deinit() catch {};
    std.builtin.default_panic(message, error_return_trace, ret_addr);
}

pub const std_options = std.Options{
    .logFn = logFn,
};

/// copy of std.log.defaultLog, but with a carriage return
pub fn logFn(comptime message_level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    nosuspend {
        writer.print(level_txt ++ prefix2 ++ format ++ "\r\n", args) catch return;
        bw.flush() catch return;
    }
}

var global_term_manager: ?*TermManager = null;

const termi = @import("termi");
const Input = termi.Input;
const chars = termi.chars;
const CSI = chars.CSI;
const ProgressiveEnhancement = termi.ProgressiveEnhancement;
const TermManager = termi.TermManager;

const std = @import("std");
const posix = std.posix;
const meta = std.meta;
