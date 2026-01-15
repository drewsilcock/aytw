const std = @import("std");

const aytw = @import("aytw");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var game = try aytw.Game.init(allocator, 6, .{
        .mode = .standard,
        .names = &[_][]const u8{ "Albert", "Bill", "Carl", "Daisy", "Emily", "Faith" },
    });
    defer game.deinit();

    std.debug.print("Game initialised\n", .{});

    try game.printProbabilities();

    std.debug.print("\nApplying truth booth #1 – Albert and Daisy don't match.\n", .{});

    try game.applyTruthBooth(0, 0, false);

    try game.printProbabilities();
}
