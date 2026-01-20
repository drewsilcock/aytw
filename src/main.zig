const std = @import("std");

const aytw = @import("aytw");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    //try standard3Example(allocator);
    //std.debug.print("\n##############\n\n", .{});
    //try standard11Example(allocator);
    try bisexualSeason8Example(allocator);
}

/// Run standard mode example with 3 men and 3 women.
fn standard3Example(allocator: std.mem.Allocator) !void {
    // https://github.com/daturkel/ayto/blob/ce7b53c962949c46a87f36352ecd6200a913a1be/README.md
    var game = try aytw.Game.init(allocator, 6, .{
        .mode = .standard,
        .names = &.{ "Albert", "Bill", "Carl", "Daisy", "Emily", "Faith" },
    });
    defer game.deinit();

    std.debug.print("Game initialised, num remaining scenarios = {d}\n", .{game.numRemainingScenarios()});
    try game.printProbabilities();

    std.debug.print(
        "\nApplied truth booth #1 – Albert + Daisy = fail, num remaining scenarios = {d}\n",
        .{game.numRemainingScenarios()},
    );
    try game.applyTruthBooth(0, 0, false);
    try game.printProbabilities();

    std.debug.print(
        "\nApplied matchup n# 1 – (Albert, Emily), (Bill, Daisy), (Carl, Faith) = 1 beam, num remaining scenarios = {d}\n",
        .{game.numRemainingScenarios()},
    );
    try game.applyMatchup(&.{ 1, 0, 2 }, 1);
    try game.printProbabilities();
}

fn standard11Example(allocator: std.mem.Allocator) !void {
    // https://github.com/daturkel/ayto/blob/ce7b53c962949c46a87f36352ecd6200a913a1be/demo.ipynb
    var game = try aytw.Game.init(allocator, 22, .{
        .mode = .standard,
        .names = &.{
            // Male names
            "Al", // 0
            "Bob", // 1
            "Chuck", // 2
            "Dale", // 3
            "Evan", // 4
            "Frank", // 5
            "Graham", // 6
            "Hugh", // 7
            "Ike", // 8
            "James", // 9
            "Kirk", // 10
            // Female names
            "Lauren", // 0
            "Mandy", // 1
            "Nora", // 2
            "Olivia", // 3
            "Pam", // 4
            "Quinn", // 5
            "Riley", // 6
            "Sam", // 7
            "Tara", // 8
            "Uma", // 9
            "Violet", // 10
        },
    });
    defer game.deinit();

    std.debug.print("Game initialised, num remaining scenarios = {d}\n", .{game.numRemainingScenarios()});
    try game.printProbabilities();

    try game.applyTruthBooth(0, 1, false);
    std.debug.print(
        "\nApplied truth booth – Al + Mandy = fail, num remaining scenarios = {d}\n",
        .{game.numRemainingScenarios()},
    );
    try game.printProbabilities();

    try game.applyMatchup(&.{ 2, 1, 3, 0, 4, 5, 6, 5, 8, 9, 10 }, 3);
    std.debug.print(
        "\nApplied matchup – (Al, Nora), (Bob, Mandy), (Chuck, Olivia), (Dale, Lauren), (Evan, Pam), (Frank, Quinn), (Graham, Riley), (Hugh, Quinn), (Ike, Tara), (James, Uma), (Kirk, Violet) = 3 beams, num remaining scenarios = {d}\n",
        .{game.numRemainingScenarios()},
    );
    try game.printProbabilities();
}

// Construct the Season 8 bisexual game (spoilers).
// https://github.com/daturkel/pyto/blob/master/AYTO_S8.ipynb
fn bisexualSeason8Example(allocator: std.mem.Allocator) !void {
    const names = &.{
        "Aasha", // 0
        "Amber", // 1
        "Basit", // 2
        "Brandon", // 3
        "Danny", // 4
        "Jasmine", // 5
        "Jenna", // 6
        "Jonathan", // 7
        "Justin", // 8
        "Kai", // 9
        "Kari", // 10
        "Kylie", // 11
        "Max", // 12
        "Nour", // 13
        "Paige", // 14
        "Remy", // 15
    };

    var game = try aytw.Game.init(allocator, 16, .{
        .mode = .bisexual,
        .names = names,
    });
    defer game.deinit();

    std.debug.print("Game initialised, num remaining scenarios = {d}\n", .{game.numRemainingScenarios()});
    try game.printProbabilities();

    const tik = std.time.nanoTimestamp();
    try game.applyTruthBooth(8, 13, false);
    const tok = std.time.nanoTimestamp();
    std.debug.print(
        "Applied truth booth – Justin + Nour = fail, num remaining scenarios = {d}, took {d} ns\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
}
