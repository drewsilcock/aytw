const std = @import("std");
const cli = @import("cli");
const seasons = @import("seasons");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return error.MissingSubcommand;
    }

    const subcmd = args[1];

    if (std.mem.eql(u8, subcmd, "replay")) {
        if (args.len < 3) {
            std.debug.print("Usage: aytw replay <season-id>\n", .{});
            std.debug.print("Available seasons:\n", .{});
            for (seasons.all_seasons.keys()) |k| {
                std.debug.print("  {s}\n", .{k});
            }
            return error.MissingSeasonId;
        }
        const season = seasons.all_seasons.get(args[2]) orelse {
            std.debug.print("Unknown season '{s}'\n", .{args[2]});
            std.debug.print("Available seasons:\n", .{});
            for (seasons.all_seasons.keys()) |k| {
                std.debug.print("  {s}\n", .{k});
            }
            return error.UnknownSeason;
        };
        try cli.runReplay(season, allocator);
    } else if (std.mem.eql(u8, subcmd, "play")) {
        try cli.runPlay(allocator);
    } else {
        std.debug.print("Unknown subcommand '{s}'\n", .{subcmd});
        printUsage();
        return error.UnknownSubcommand;
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  aytw replay <season-id>   Replay a pre-defined season step by step
        \\  aytw play                 Play an interactive game
        \\
    , .{});
}
