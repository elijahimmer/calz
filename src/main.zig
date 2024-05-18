pub fn main() !void {
    const stdout_file = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout_file.writer());
    const stdout = bw.writer();

    const stdin_file = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin_file.reader());
    const stdin = br.reader();

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
    try Command.home.print(stdout, .{});

    main_loop: while (true) {
        try stdout.print(">>> ", .{});
        try bw.flush();

        const line_raw = readLine(stdout_file.writer(), stdin) catch |err| {
            if (err == error.ctrl_c) {
                try stdout.print("\r\ntype ':q' to exit\r\n", .{});
            } else log.err("{s}", .{@errorName(err)});

            continue :main_loop;
        };

        const line = mem.trim(u8, line_raw.constSlice(), &std.ascii.whitespace);

        if (mem.eql(u8, line, ":q")) break :main_loop;

        try stdout.print("\r\n   '{s}' :: line\r\n", .{line});
    }
}

const ReadLineError = error{
    ctrl_c,
};

pub fn readLine(stdout: anytype, stdin: anytype) anyerror!BoundedArray(u8, line_length) {
    var line = BoundedArray(u8, line_length){};
    var cursor_pos: LinePos = 0;

    read_loop: while (true) {
        assert(cursor_pos <= line.len);

        const input = try Input.parse.readOneInput(stdin);

        if (input.input_type == .release) continue;

        if (@as(Input.KeyCodeTag, input.key_code) == .text and input.key_code.text == 'c' and input.modifiers.onlyActive(.ctrl)) return ReadLineError.ctrl_c;
        switch (input.key_code) {
            .text => |text| {
                if (cursor_pos == line.len) {
                    try line.append(text);
                    try stdout.writeByte(text);
                    cursor_pos +|= 1;
                } else {
                    try line.insert(cursor_pos, text);

                    const line_to_print = line.constSlice()[cursor_pos..];

                    try stdout.print("{s}", .{line_to_print});
                    try Command.move_left.print(stdout, .{line_to_print.len - 1});
                    cursor_pos +|= 1;
                }
            },
            .special => |special| switch (special) {
                .right => {
                    cursor_pos +|= 1;
                    if (cursor_pos > line.len) cursor_pos = line.len else {
                        try Command.move_right.print(stdout, .{1});
                    }
                },
                .left => {
                    if (cursor_pos > 0) {
                        cursor_pos -|= 1;
                        try Command.move_left.print(stdout, .{1});
                    }
                },
                .backspace, .delete => |spec| delete: {
                    if (spec == .backspace) {
                        if (line.len == 0 or cursor_pos == 0) break :delete;

                        cursor_pos -|= 1;
                        try Command.move_left.print(stdout, .{1});
                    } else if (spec == .delete and cursor_pos >= line.len) break :delete;

                    _ = line.orderedRemove(cursor_pos);
                    const line_to_print = line.constSlice()[cursor_pos..];
                    try stdout.print("{s} ", .{line_to_print});
                    try Command.move_left.print(stdout, .{line_to_print.len + 1});
                },
                .enter => break :read_loop,
                else => {},
            },
            .unknown => {},
        }
    }

    return line;
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

const LinePos = u8;
const line_length = std.math.maxInt(LinePos);

const termi = @import("termi");
const Input = termi.Input;
const chars = termi.chars;
const ProgressiveEnhancement = termi.ProgressiveEnhancement;
const TermManager = termi.TermManager;
const Command = termi.Command;

const std = @import("std");
const posix = std.posix;
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;
const BoundedArray = std.BoundedArray;
const log = std.log.scoped(.calz);
