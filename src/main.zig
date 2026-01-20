const std = @import("std");

const aytw = @import("aytw");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    //try standard3Example(allocator);
    //std.debug.print("\n##############\n\n", .{});
    //try standard11Example(allocator);
    //try bisexual6Example(allocator);
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

fn bisexual6Example(allocator: std.mem.Allocator) !void {
    var game = try aytw.Game.init(allocator, 6, .{
        .mode = .bisexual,
        .names = &.{ "Albert", "Bill", "Carl", "Daisy", "Emily", "Faith" },
    });
    defer game.deinit();

    std.debug.print("Game initialised, num remaining scenarios = {d}\n", .{game.numRemainingScenarios()});
    try game.printProbabilities();

    std.debug.print(
        "\nApplied truth booth #1 – Albert + Daisy = fail, num remaining scenarios = {d}\n",
        .{game.numRemainingScenarios()},
    );
    try game.applyTruthBooth(0, 3, false);
    try game.printProbabilities();

    //std.debug.print(
    //    "\nApplied matchup n# 1 – (Albert, Emily), (Bill, Daisy), (Carl, Faith) = 1 beam, num remaining scenarios = {d}\n",
    //    .{game.numRemainingScenarios()},
    //);
    //try game.applyMatchup(&.{ 1, 0, 2 }, 1);
    //try game.printProbabilities();
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

    var tik = std.time.milliTimestamp();
    try game.applyTruthBooth(8, 13, false);
    var tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied truth booth – Justin + Nour = fail, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyMatchup(&.{
        14, // Aasha -> Paige
        13, // Amber -> Nour
        7, // Basit -> Jonathan
        15, // Brandon -> Remy
        9, // Danny -> Kai
        6, // Jasmine -> Jenna
        5, // Jenna -> Jasmine
        2, // Jonathan -> Basit
        12, // Justin -> Max
        4, // Kai -> Danny
        11, // Kari -> Kylie
        10, // Kylie -> Kari
        8, // Max -> Justin
        1, // Nour -> Amber
        0, // Paige -> Aasha
        3, // Remy -> Brandon
    }, 2);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied matchup – (Nour, Amber), (Kari, Kylie), (Max, Justin), (Basit, Jonathan), (Aasha, Paige), (Remy, Brandon), (Jasmine, Jenna), (Kai, Danny) = 2, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyTruthBooth(3, 15, false);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied truth booth – Brandon + Remy = fail, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyMatchup(&.{
        3, // Aasha -> Brandon
        13, // Amber -> Nour
        7, // Basit -> Jonathan
        0, // Brandon -> Aasha
        15, // Danny -> Remy
        8, // Jasmine -> Justin
        9, // Jenna -> Kai
        2, // Jonathan -> Basit
        5, // Justin -> Jasmine
        6, // Kai -> Jenna
        11, // Kari -> Kylie
        10, // Kylie -> Kari
        14, // Max -> Paige
        1, // Nour -> Amber
        12, // Paige -> Max
        4, // Remy -> Danny
    }, 2);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied matchup – (Aasha, Brandon), (Amber, Nour), (Basit, Jonathan), (Danny, Remy), (Jasmine, Justin), (Jenna, Kai), (Kari, Kylie), (Max, Paige) = 2, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyTruthBooth(6, 9, false);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied matchup – Jenna + Kai = fail, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyMatchup(&.{
        12, // Aasha -> Max
        14, // Amber -> Paige
        15, // Basit -> Remy
        7, // Brandon -> Jonathan
        9, // Danny -> Kai
        13, // Jasmine -> Nour
        8, // Jenna -> Justin
        3, // Jonathan -> Brandon
        6, // Justin -> Jenna
        4, // Kai -> Danny
        11, // Kari -> Kylie
        10, // Kylie -> Kari
        0, // Max -> Aasha
        5, // Nour -> Jasmine
        1, // Paige -> Amber
        2, // Remy -> Basit
    }, 2);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied matchup – (Jonathan, Brandon), (Aasha, Max), (Paige, Amber), (Kai, Danny), (Jenna, Justin), (Remy, Basit), (Kylie, Kari), (Jasmine, Nour) = 2, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyTruthBooth(4, 6, false);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied truth booth – Danny + Jenna = fail, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyMatchup(&.{
        15, // Aasha -> Remy
        13, // Amber -> Nour
        4, // Basit -> Danny
        5, // Brandon -> Jasmine
        2, // Danny -> Basit
        3, // Jasmine -> Brandon
        14, // Jenna -> Paige
        11, // Jonathan -> Kylie
        12, // Justin -> Max
        10, // Kai -> Kari
        9, // Kari -> Kai
        7, // Kylie -> Jonathan
        8, // Max -> Justin
        1, // Nour -> Amber
        6, // Paige -> Jenna
        0, // Remy -> Aasha
    }, 1);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied matchup – (Aasha, Remy), (Amber, Nour), (Basit, Danny), (Brandon, Jasmine), (Jenna, Paige), (Jonathan, Kylie), (Justin, Max), (Kai, Kari) = 1, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyTruthBooth(10, 11, false);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied truth booth – Kari + Kylie = fail, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();

    tik = std.time.milliTimestamp();
    try game.applyMatchup(&.{
        9, // Aasha -> Kai
        13, // Amber -> Nour
        15, // Basit -> Remy
        12, // Brandon -> Max
        10, // Danny -> Kari
        14, // Jasmine -> Paige
        11, // Jenna -> Kylie
        8, // Jonathan -> Justin
        7, // Justin -> Jonathan
        0, // Kai -> Aasha
        4, // Kari -> Danny
        6, // Kylie -> Jenna
        3, // Max -> Brandon
        1, // Nour -> Amber
        5, // Paige -> Jasmine
        2, // Remy -> Basit
    }, 0);
    tok = std.time.milliTimestamp();
    std.debug.print(
        "Applied matchup – (Aasha, Kai), (Amber, Nour), (Basit, Remy), (Brandon, Max), (Jenna, Kylie), (Jonathan, Justin), (Kari, Danny), (Paige, Jasmine) = 0, num remaining scenarios = {d}, took {d} ms\n",
        .{ game.numRemainingScenarios(), tok - tik },
    );
    try game.printProbabilities();
}
