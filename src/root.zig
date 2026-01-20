//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

const Table = @import("prettytable").Table;

const maths = @import("maths.zig");

var male_names = [_][]const u8{
    "Andy",
    "Bluey",
    "Bri",
    "Bruce",
    "Bruno",
    "Carn",
    "Clarence",
    "Dazza",
    "Dennis",
    "Dubbo",
    "Duke",
    "Duncan",
    "Norman",
    "Gary",
    "Jack",
    "Johnno",
    "Julius",
    "Karlos",
    "Keith",
    "Ken",
    "Lenny",
    "Mark",
    "Merv",
    "Neddy",
    "Patch",
    "Red",
    "Russ",
    "Rex",
    "Ridge",
    "Ryan",
    "Sly",
    "Steve",
    "Tiberius",
    "Ty",
    "Wozza",
};

var female_names = [_][]const u8{
    "Aurora",
    "Betty",
    "Birrel",
    "Brolga",
    "Cassie",
    "Charlene",
    "Colleen",
    "Dawn",
    "Di",
    "Fluffy",
    "Kitty",
    "Kylie",
    "Lily",
    "Liz",
    "Maggie",
    "Maureen",
    "Muriel",
    "Naomi",
    "Peppa",
    "Pippa",
    "Poly",
    "Rose",
    "Shade",
    "Shazza",
    "Sheila",
    "Skye",
    "Tabi",
    "Thigana",
};

pub const GameOptions = struct {
    mode: GameMode,
    names: ?[]const []const u8,
};

pub const GameMode = enum {
    standard,
    bisexual,
};

pub const Game = struct {
    // TODO: Allow for up to n//3 throuples
    n: u32, // Total number of contestants.
    m: u32, // Half number of contestants, commonly used in standard mode.
    mode: GameMode,
    names: [][]const u8,
    eliminated: std.bit_set.DynamicBitSetUnmanaged,
    num_total_scenarios: usize,
    num_remaining_scenarios: usize,
    probabilities: []u64, // TODO: This is more accurately describe as "possibilities".
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new game instance.
    /// n = number of contestants
    /// options = game options
    pub fn init(allocator: std.mem.Allocator, n: u32, options: GameOptions) !Self {
        if (n % 2 != 0) {
            return error.InvalidNumberOfContestants;
        }

        const m = n / 2;

        var names: [][]const u8 = try allocator.alloc([]const u8, n);
        errdefer allocator.free(names);

        if (options.names) |input_names| {
            @memcpy(names, input_names);
        } else {
            // Choose names randomly by shuffling the list and choosing the first M
            // male names and N female names.
            var prng: std.Random.DefaultPrng = .init(blk: {
                var seed: u64 = undefined;
                try std.posix.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            });

            const rand = prng.random();
            rand.shuffle([]const u8, &male_names);
            rand.shuffle([]const u8, &female_names);

            names = try allocator.alloc([]const u8, n);
            errdefer names.deinit(allocator);
            @memcpy(names[0..m], male_names[0..m]);
            @memcpy(names[m..], female_names[0..m]);
        }

        const num_scenarios = switch (options.mode) {
            .standard => maths.factorial(m),
            .bisexual => maths.doubleFactorial(n - 1),
        };

        const num_possibilities = switch (options.mode) {
            // In standard, each male could match w/ each female.
            .standard => m * m,
            // In bisexual, each person can match w/ anyone else apart from
            // themselves. To make the 2d array maths easier, we allocate a nxn
            // array where the diagonal values are always 0.
            .bisexual => n * n,
        };

        // Instead of storing the normalised probabilities, we store the n#
        // scenarios that are compatible with the given pairing; to get the
        // probability, simple divide this value by num_remaining_scenarios.
        var probabilities = try allocator.alloc(u64, num_possibilities);
        errdefer allocator.free(probabilities);

        const starting_num_poss = switch (options.mode) {
            // In standard, each male can match with each female giving
            // probability 1/M for each.
            .standard => num_scenarios / m,
            // In bisexual, each person can match with any other person apart
            // from themselves, giving N-1 possibilities and so probability
            // 1/(N-1).
            .bisexual => num_scenarios / (n - 1),
        };

        for (0..num_possibilities) |k| {
            // If we're on the diagonal and in bisexual mode, num possibilties is 0.
            const i = k % n;
            const j = k / n;
            if (options.mode == .bisexual and i == j) {
                probabilities[k] = 0;
            } else {
                probabilities[k] = starting_num_poss;
            }
        }

        var eliminated = try std.bit_set.DynamicBitSetUnmanaged.initEmpty(allocator, num_scenarios);
        errdefer eliminated.deinit(allocator);

        return Self{
            .n = n,
            .m = m,
            .mode = options.mode,
            .names = names,
            .eliminated = eliminated,
            .num_total_scenarios = num_scenarios,
            .num_remaining_scenarios = num_scenarios,
            .probabilities = probabilities,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.names);
        self.allocator.free(self.probabilities);
        self.eliminated.deinit(self.allocator);
    }

    pub fn numRemainingScenarios(self: Self) u64 {
        return self.num_remaining_scenarios;
    }

    pub fn applyMatchup(self: *Self, matchup: []const u32, num_correct: u8) !void {
        switch (self.mode) {
            .standard => {
                std.debug.assert(matchup.len == self.m);
                std.debug.assert(num_correct <= self.m);
            },
            .bisexual => {
                std.debug.assert(matchup.len == self.n);
                std.debug.assert(num_correct <= self.n);

                // In order to be a valid matchup, it must be symmetric, i.e.
                // matchup[i]=j implies matchup[j]=i.
                for (0..matchup.len) |i| {
                    const j = matchup[i];
                    std.debug.assert(matchup[j] == i);
                }
            },
        }

        @memset(self.probabilities, 0);

        const size = switch (self.mode) {
            .standard => self.m,
            .bisexual => self.n,
        };

        const perm = try self.allocator.alloc(u32, size);
        defer self.allocator.free(perm);

        // Available array only needed for bisexual permutation generation, not
        // standard mode, but it's cheap to allocate a small array so we just do
        // it for either.
        const available = try self.allocator.alloc(bool, size);
        defer self.allocator.free(available);

        for (0..self.num_total_scenarios) |k| {
            if (self.eliminated.isSet(k)) {
                continue;
            }

            switch (self.mode) {
                .standard => self.getScenarioStandard(k, perm),
                .bisexual => self.getScenarioBisexual(k, available, perm),
            }

            // For bisexual mode, as we are using a full list of all people,
            // each correct pair will appear twice in our list, so n# matching
            // pairs is half the n# matching elements in the full slice.
            const num_matches = maths.countMatching(u32, perm, matchup);
            const num_pairs = if (self.mode == .bisexual) num_matches / 2 else num_matches;
            if (num_pairs != num_correct) {
                self.eliminated.set(k);
                self.num_remaining_scenarios -= 1;
                continue;
            }

            for (0..perm.len) |i| {
                const j = perm[i];
                const prob_idx = i * size + j;
                self.probabilities[prob_idx] += 1;
            }
        }
    }

    pub fn applyTruthBooth(self: *Self, idx1: usize, idx2: usize, is_match: bool) !void {
        switch (self.mode) {
            .standard => {
                std.debug.assert(idx1 < self.m);
                std.debug.assert(idx2 < self.m);
            },
            .bisexual => {
                std.debug.assert(idx1 < self.n);
                std.debug.assert(idx2 < self.n);
                std.debug.assert(idx1 != idx2);
            },
        }

        // For standard mode, idx1 = male, idx2 = female
        // For bisexual mode, idx1 = row, idx2 = column
        @memset(self.probabilities, 0);

        const size = switch (self.mode) {
            .standard => self.m,
            .bisexual => self.n,
        };

        const perm = try self.allocator.alloc(u32, size);
        defer self.allocator.free(perm);

        // Available array only needed for bisexual permutation generation, not
        // standard mode, but it's cheap to allocate a small array so we just do
        // it for either.
        const available = try self.allocator.alloc(bool, size);
        defer self.allocator.free(available);

        for (0..self.num_total_scenarios) |k| {

            // Instead of keeping bitmask for every iteration, could we keep
            // array of remaining indices? That way, we only iterate through the
            // remaining possibilities, potentially saving time.
            if (self.eliminated.isSet(k)) {
                continue;
            }

            switch (self.mode) {
                .standard => self.getScenarioStandard(k, perm),
                .bisexual => self.getScenarioBisexual(k, available, perm),
            }

            if ((perm[idx1] == idx2) != is_match) {
                self.eliminated.set(k);
                self.num_remaining_scenarios -= 1;
                continue;
            }

            for (0..perm.len) |i| {
                const j = perm[i];
                const prob_idx = i * size + j;
                self.probabilities[prob_idx] += 1;
            }
        }
    }

    pub fn getPossibilities(self: *const Self, out: []u64) void {
        @memcpy(out, self.probabilities);
    }

    pub fn getProbabilities(self: *const Self, out: []f64) !void {
        const size = if (self.mode == .standard) self.m else self.n;
        std.debug.assert(out.len == size * size);

        for (0..size) |i| {
            for (0..size) |j| {
                const k = i * size + j;
                const num_poss = self.probabilities[k];
                out[k] = @as(f32, @floatFromInt(num_poss)) / @as(f32, @floatFromInt(self.num_remaining_scenarios));
            }
        }
    }

    pub fn printProbabilities(self: *const Self) !void {
        var table = Table.init(self.allocator);
        defer table.deinit();

        const perm_size = if (self.mode == .standard) self.m else self.n;
        const row_size = perm_size + 1;

        var row = try self.allocator.alloc([]const u8, row_size);
        defer self.allocator.free(row);

        row[0] = "";

        switch (self.mode) {
            // In standard mode, the headers are just the female names.
            .standard => @memcpy(row[1..], self.names[self.m..self.n]),
            // In bisexual mode, we need a column and a row per person.
            .bisexual => @memcpy(row[1..], self.names),
        }
        try table.setTitle(row);

        var printBuf: [2048]u8 = undefined;
        var bufIdx: usize = 0;

        // i = male index / row index, j = female index / column index
        for (0..perm_size) |i| {
            row[0] = self.names[i];
            for (0..perm_size) |j| {
                const num_poss = self.probabilities[i * perm_size + j];
                const prob = @as(f32, @floatFromInt(num_poss)) / @as(f32, @floatFromInt(self.num_remaining_scenarios));
                const text = try std.fmt.bufPrint(printBuf[bufIdx..], "{d: >6.2}%", .{prob * 100});
                bufIdx += text.len;
                row[j + 1] = text;
            }
            try table.addRow(row);
        }

        try table.print_tty(false);
    }

    fn getScenarioStandard(self: *const Self, k: usize, out: []u32) void {
        maths.getPermutation(self.m, k, out);
    }

    fn getScenarioBisexual(self: *const Self, k: usize, available: []bool, out: []u32) void {
        maths.getKthPairing(self.n, k, available, out);
    }
};

// Run standard mode example with 3 men and 3 women.
// https://github.com/daturkel/ayto/blob/ce7b53c962949c46a87f36352ecd6200a913a1be/README.md
test "standard mode M=3" {
    const allocator = std.testing.allocator;

    var game = try Game.init(allocator, 6, .{
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

// https://github.com/daturkel/ayto/blob/ce7b53c962949c46a87f36352ecd6200a913a1be/demo.ipynb
test "standard mode M=11" {
    const allocator = std.testing.allocator;

    var game = try Game.init(allocator, 22, .{
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

test "bisexual N=16" {
    const allocator = std.testing.allocator;

    const n = 16;

    var game = try Game.init(allocator, n, .{
        .mode = .bisexual,
        .names = &.{
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
        },
    });
    defer game.deinit();

    var poss = [_]u64{0} ** (n * n);
    defer allocator.free(poss);

    // Initial game state
    try std.testing.expectEqual(2027025, game.numRemainingScenarios());
    game.getPossibilities(&poss);
    try std.testing.expectEqualSlices(u64, &.{
        0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500, 13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,      13513500,
        13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 13513500, 0.0,
    }, &poss);

    // Episode 1 – truth booth
    try game.applyTruthBooth(8, 13, false);
    try std.testing.expectEqual(1891890, game.numRemainingScenarios());
    game.getPossibilities(&poss);
    try std.testing.expectEqualSlices(u64, &.{
        0.0, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600, 12612600,
    }, &poss);

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

    try game.applyTruthBooth(3, 15, false);

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

    try game.applyTruthBooth(6, 9, false);

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

    try game.applyTruthBooth(4, 6, false);

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

    try game.applyTruthBooth(10, 11, false);

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
}
