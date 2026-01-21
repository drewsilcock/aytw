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
            if (options.mode == .bisexual and (k % n) == (k / n)) {
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

    pub fn getProbabilities(self: *const Self, out: []f64) !void {
        std.debug.assert(out.len == self.probabilities.len);

        for (0..self.probabilities.len) |k| {
            const num_poss = self.probabilities[k];
            out[k] = @as(f32, @floatFromInt(num_poss)) / @as(f32, @floatFromInt(self.num_remaining_scenarios));
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

    pub fn findOptimalTruthBooth(self: *const Self) [2]usize {
        // As truth booth is a binary result (either match or no match), the
        // entropy follows the binomial entropy function:
        // H(X) = -plog(p) - (1-p)log(p)
        // This has a maximum at p=50% so we want to find the two pairs with
        // probability closest to 50%.
        const size = if (self.mode == .standard) self.m else self.n;
        var result = [_]usize{ 0, 0 };

        var best_dist: u64 = std.math.maxInt(u64);

        for (0..self.probabilities.len) |k| {
            const num_poss = self.probabilities[k];

            // Finding p=0.5 is the same as finding pair where n# pair
            // possibilities = total n# scenarios / 2. Easier to multiply than
            // divide.

            // Technically, this int cast is unsafe, but it's never going to be
            // the case that n# remaining scenarios > max i64 as this isn't
            // computable.
            const dist_to_opt = @abs(@as(i64, @intCast(self.num_remaining_scenarios)) - @as(i64, @intCast(num_poss * 2)));

            if (dist_to_opt < best_dist) {
                best_dist = dist_to_opt;

                result[0] = k % size;
                result[1] = k / size;
            }
        }

        return result;
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

    try std.testing.expectEqual(6, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        2, 2, 2,
        2, 2, 2,
        2, 2, 2,
    }, game.probabilities);

    // Truth booth – Albert + Daisy = no match
    try game.applyTruthBooth(0, 0, false);
    try std.testing.expectEqual(4, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0, 2, 2,
        2, 1, 1,
        2, 1, 1,
    }, game.probabilities);

    // Matchup – 1 beam
    try game.applyMatchup(&.{ 1, 0, 2 }, 1);
    try std.testing.expectEqual(2, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0, 1, 1,
        1, 0, 1,
        1, 1, 0,
    }, game.probabilities);
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

    try game.applyTruthBooth(0, 1, false);

    try game.applyMatchup(&.{ 2, 1, 3, 0, 4, 5, 6, 5, 8, 9, 10 }, 3);
}

// This test is made up and isn't an already established baseline.
test "bisexual N=6" {
    var game = try Game.init(std.testing.allocator, 6, .{
        .mode = .bisexual,
        .names = &.{ "Albert", "Bill", "Carl", "Daisy", "Emily", "Faith" },
    });
    defer game.deinit();

    try std.testing.expectEqual(15, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0, 3, 3, 3, 3, 3,
        3, 0, 3, 3, 3, 3,
        3, 3, 0, 3, 3, 3,
        3, 3, 3, 0, 3, 3,
        3, 3, 3, 3, 0, 3,
        3, 3, 3, 3, 3, 0,
    }, game.probabilities);

    try game.applyTruthBooth(0, 3, false);
    try std.testing.expectEqual(12, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0, 3, 3, 0, 3, 3,
        3, 0, 2, 3, 2, 2,
        3, 2, 0, 3, 2, 2,
        0, 3, 3, 0, 3, 3,
        3, 2, 2, 3, 0, 2,
        3, 2, 2, 3, 2, 0,
    }, game.probabilities);

    try game.applyMatchup(&.{ 4, 3, 5, 1, 0, 2 }, 1);
    try std.testing.expectEqual(5, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0, 1, 1, 0, 2, 1,
        1, 0, 1, 2, 0, 1,
        1, 1, 0, 1, 1, 1,
        0, 2, 1, 0, 1, 1,
        2, 0, 1, 1, 0, 1,
        1, 1, 1, 1, 1, 0,
    }, game.probabilities);
}

// https://github.com/daturkel/pyto/blob/master/AYTO_S8.ipynb
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

    // Initial game state
    try std.testing.expectEqual(2027025, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135, 135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,    135135,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0.0,
    }, game.probabilities);

    // Episode 1&2 – truth booth – Justin + Nour = no match
    try game.applyTruthBooth(8, 13, false);
    try std.testing.expectEqual(1891890, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,      124740, 124740, 124740, 124740, 124740, 124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        124740, 0,      124740, 124740, 124740, 124740, 124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        124740, 124740, 0,      124740, 124740, 124740, 124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        124740, 124740, 124740, 0,      124740, 124740, 124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        124740, 124740, 124740, 124740, 0,      124740, 124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        124740, 124740, 124740, 124740, 124740, 0,      124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        124740, 124740, 124740, 124740, 124740, 124740, 0,      124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        124740, 124740, 124740, 124740, 124740, 124740, 124740, 0,      135135, 124740, 124740, 124740, 124740, 135135, 124740, 124740,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0,      135135, 135135, 135135, 135135, 0,      135135, 135135,
        124740, 124740, 124740, 124740, 124740, 124740, 124740, 124740, 135135, 0,      124740, 124740, 124740, 135135, 124740, 124740,
        124740, 124740, 124740, 124740, 124740, 124740, 124740, 124740, 135135, 124740, 0,      124740, 124740, 135135, 124740, 124740,
        124740, 124740, 124740, 124740, 124740, 124740, 124740, 124740, 135135, 124740, 124740, 0,      124740, 135135, 124740, 124740,
        124740, 124740, 124740, 124740, 124740, 124740, 124740, 124740, 135135, 124740, 124740, 124740, 0,      135135, 124740, 124740,
        135135, 135135, 135135, 135135, 135135, 135135, 135135, 135135, 0,      135135, 135135, 135135, 135135, 0,      135135, 135135,
        124740, 124740, 124740, 124740, 124740, 124740, 124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 0,      124740,
        124740, 124740, 124740, 124740, 124740, 124740, 124740, 124740, 135135, 124740, 124740, 124740, 124740, 135135, 124740, 0,
    }, game.probabilities);

    // Episode 1&2 – matchup, 2 beams
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
    try std.testing.expectEqual(160060, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,     8380,  8592,  8592,  8592,  8592,  8592,  8592,  9060,  8592,  8592,  8592,  8380,  9060,  39260, 8592,
        8380,  0,     8380,  8380,  8380,  8380,  8380,  8380,  9060,  8380,  8380,  8380,  8160,  42280, 8380,  8380,
        8592,  8380,  0,     8592,  8592,  8592,  8592,  39260, 9060,  8592,  8592,  8592,  8380,  9060,  8592,  8592,
        8592,  8380,  8592,  0,     8592,  8592,  8592,  8592,  9060,  8592,  8592,  8592,  8380,  9060,  8592,  39260,
        8592,  8380,  8592,  8592,  0,     8592,  8592,  8592,  9060,  39260, 8592,  8592,  8380,  9060,  8592,  8592,
        8592,  8380,  8592,  8592,  8592,  0,     39260, 8592,  9060,  8592,  8592,  8592,  8380,  9060,  8592,  8592,
        8592,  8380,  8592,  8592,  8592,  39260, 0,     8592,  9060,  8592,  8592,  8592,  8380,  9060,  8592,  8592,
        8592,  8380,  39260, 8592,  8592,  8592,  8592,  0,     9060,  8592,  8592,  8592,  8380,  9060,  8592,  8592,
        9060,  9060,  9060,  9060,  9060,  9060,  9060,  9060,  0,     9060,  9060,  9060,  42280, 0,     9060,  9060,
        8592,  8380,  8592,  8592,  39260, 8592,  8592,  8592,  9060,  0,     8592,  8592,  8380,  9060,  8592,  8592,
        8592,  8380,  8592,  8592,  8592,  8592,  8592,  8592,  9060,  8592,  0,     39260, 8380,  9060,  8592,  8592,
        8592,  8380,  8592,  8592,  8592,  8592,  8592,  8592,  9060,  8592,  39260, 0,     8380,  9060,  8592,  8592,
        8380,  8160,  8380,  8380,  8380,  8380,  8380,  8380,  42280, 8380,  8380,  8380,  0,     9060,  8380,  8380,
        9060,  42280, 9060,  9060,  9060,  9060,  9060,  9060,  0,     9060,  9060,  9060,  9060,  0,     9060,  9060,
        39260, 8380,  8592,  8592,  8592,  8592,  8592,  8592,  9060,  8592,  8592,  8592,  8380,  9060,  0,     8592,
        8592,  8380,  8592,  39260, 8592,  8592,  8592,  8592,  9060,  8592,  8592,  8592,  8380,  9060,  8592,  0,
    }, game.probabilities);

    // Episode 3 – truth booth – brandon + remy = no match
    try game.applyTruthBooth(3, 15, false);
    try std.testing.expectEqual(120800, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,     5632,  5806,  8592, 5806,  5806,  5806,  5806,  6040,  5806,  5806,  5806,  5632,  6040,  33824, 8592,
        5632,  0,     5632,  8380, 5632,  5632,  5632,  5632,  6040,  5632,  5632,  5632,  5440,  36240, 5632,  8380,
        5806,  5632,  0,     8592, 5806,  5806,  5806,  33824, 6040,  5806,  5806,  5806,  5632,  6040,  5806,  8592,
        8592,  8380,  8592,  0,    8592,  8592,  8592,  8592,  9060,  8592,  8592,  8592,  8380,  9060,  8592,  0,
        5806,  5632,  5806,  8592, 0,     5806,  5806,  5806,  6040,  33824, 5806,  5806,  5632,  6040,  5806,  8592,
        5806,  5632,  5806,  8592, 5806,  0,     33824, 5806,  6040,  5806,  5806,  5806,  5632,  6040,  5806,  8592,
        5806,  5632,  5806,  8592, 5806,  33824, 0,     5806,  6040,  5806,  5806,  5806,  5632,  6040,  5806,  8592,
        5806,  5632,  33824, 8592, 5806,  5806,  5806,  0,     6040,  5806,  5806,  5806,  5632,  6040,  5806,  8592,
        6040,  6040,  6040,  9060, 6040,  6040,  6040,  6040,  0,     6040,  6040,  6040,  36240, 0,     6040,  9060,
        5806,  5632,  5806,  8592, 33824, 5806,  5806,  5806,  6040,  0,     5806,  5806,  5632,  6040,  5806,  8592,
        5806,  5632,  5806,  8592, 5806,  5806,  5806,  5806,  6040,  5806,  0,     33824, 5632,  6040,  5806,  8592,
        5806,  5632,  5806,  8592, 5806,  5806,  5806,  5806,  6040,  5806,  33824, 0,     5632,  6040,  5806,  8592,
        5632,  5440,  5632,  8380, 5632,  5632,  5632,  5632,  36240, 5632,  5632,  5632,  0,     6040,  5632,  8380,
        6040,  36240, 6040,  9060, 6040,  6040,  6040,  6040,  0,     6040,  6040,  6040,  6040,  0,     6040,  9060,
        33824, 5632,  5806,  8592, 5806,  5806,  5806,  5806,  6040,  5806,  5806,  5806,  5632,  6040,  0,     8592,
        8592,  8380,  8592,  0,    8592,  8592,  8592,  8592,  9060,  8592,  8592,  8592,  8380,  9060,  8592,  0,
    }, game.probabilities);

    // Episode 3 – matchup, 2 beams
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
    try std.testing.expectEqual(26907, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,    1035,  1096,  4116, 1584, 1774, 1778, 1096,  1788, 1718, 1096,  1096,  1603, 1125,  4046, 1956,
        1035, 0,     637,   1329, 1027, 1107, 1096, 637,   1215, 1093, 637,   637,   1077, 12956, 1098, 1326,
        1096, 637,   0,     1408, 1092, 1173, 1161, 12171, 1215, 1159, 693,   693,   1149, 696,   1162, 1402,
        4116, 1329,  1408,  0,    1947, 2109, 2085, 1408,  2190, 2028, 1408,  1408,  2038, 1459,  1974, 0,
        1584, 1027,  1092,  1947, 0,    1720, 1620, 1092,  1842, 4048, 1092,  1092,  1761, 1125,  1731, 4134,
        1774, 1107,  1173,  2109, 1720, 0,    4044, 1173,  2808, 1747, 1173,  1173,  1747, 1215,  1867, 2077,
        1778, 1096,  1161,  2085, 1620, 4044, 0,    1161,  1848, 2774, 1161,  1161,  1867, 1197,  1908, 2046,
        1096, 637,   12171, 1408, 1092, 1173, 1161, 0,     1215, 1159, 693,   693,   1149, 696,   1162, 1402,
        1788, 1215,  1215,  2190, 1842, 2808, 1848, 1215,  0,    1938, 1215,  1215,  4378, 0,     1818, 2222,
        1718, 1093,  1159,  2028, 4048, 1747, 2774, 1159,  1938, 0,    1159,  1159,  1882, 1195,  1892, 1956,
        1096, 637,   693,   1408, 1092, 1173, 1161, 693,   1215, 1159, 0,     12171, 1149, 696,   1162, 1402,
        1096, 637,   693,   1408, 1092, 1173, 1161, 693,   1215, 1159, 12171, 0,     1149, 696,   1162, 1402,
        1603, 1077,  1149,  2038, 1761, 1747, 1867, 1149,  4378, 1882, 1149,  1149,  0,    1197,  2684, 2077,
        1125, 12956, 696,   1459, 1125, 1215, 1197, 696,   0,    1195, 696,   696,   1197, 0,     1195, 1459,
        4046, 1098,  1162,  1974, 1731, 1867, 1908, 1162,  1818, 1892, 1162,  1162,  2684, 1195,  0,    2046,
        1956, 1326,  1402,  0,    4134, 2077, 2046, 1402,  2222, 1956, 1402,  1402,  2077, 1459,  2046, 0,
    }, game.probabilities);

    // Episode 4 – truth booth – Jenna + Kai = no match
    try game.applyTruthBooth(6, 9, false);
    try std.testing.expectEqual(24133, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,    903,   964,   4116, 1380, 1600, 1778, 964,   1788, 1718, 964,   964,   1603, 993,   2676, 1722,
        903,  0,     523,   1087, 819,  901,  1096, 523,   1083, 1093, 523,   523,   977,  12010, 986,  1086,
        964,  523,   0,     1158, 876,  960,  1161, 11291, 1083, 1159, 570,   570,   1042, 573,   1050, 1153,
        4116, 1087,  1158,  0,    1593, 1761, 2085, 1158,  1986, 2028, 1158,  1158,  1878, 1197,  1770, 0,
        1380, 819,   876,   1593, 0,    1410, 1620, 876,   1638, 4048, 876,   876,   1601, 897,   1557, 4066,
        1600, 901,   960,   1761, 1410, 0,    4044, 960,   2808, 1747, 960,   960,   1589, 993,   1717, 1723,
        1778, 1096,  1161,  2085, 1620, 4044, 0,    1161,  1848, 0,    1161,  1161,  1867, 1197,  1908, 2046,
        964,  523,   11291, 1158, 876,  960,  1161, 0,     1083, 1159, 570,   570,   1042, 573,   1050, 1153,
        1788, 1083,  1083,  1986, 1638, 2808, 1848, 1083,  0,    1938, 1083,  1083,  2906, 0,     1818, 1988,
        1718, 1093,  1159,  2028, 4048, 1747, 0,    1159,  1938, 0,    1159,  1159,  1882, 1195,  1892, 1956,
        964,  523,   570,   1158, 876,  960,  1161, 570,   1083, 1159, 0,     11291, 1042, 573,   1050, 1153,
        964,  523,   570,   1158, 876,  960,  1161, 570,   1083, 1159, 11291, 0,     1042, 573,   1050, 1153,
        1603, 977,   1042,  1878, 1601, 1589, 1867, 1042,  2906, 1882, 1042,  1042,  0,    1081,  2684, 1897,
        993,  12010, 573,   1197, 897,  993,  1197, 573,   0,    1195, 573,   573,   1081, 0,     1083, 1195,
        2676, 986,   1050,  1770, 1557, 1717, 1908, 1050,  1818, 1892, 1050,  1050,  2684, 1083,  0,    1842,
        1722, 1086,  1153,  0,    4066, 1723, 2046, 1153,  1988, 1956, 1153,  1153,  1897, 1195,  1842, 0,
    }, game.probabilities);

    // Episode 4 – matchup – 2 beams
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
    try std.testing.expectEqual(4383, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,   212,  214,  663, 240,  271, 318, 210,  270, 271,  71,   71,   749, 222,  264, 337,
        212, 0,    156,  265, 154,  201, 250, 168,  230, 198,  50,   50,   220, 1493, 478, 258,
        214, 156,  0,    227, 149,  242, 257, 1410, 230, 199,  45,   45,   211, 189,  233, 576,
        663, 265,  227,  0,   262,  321, 355, 573,  308, 313,  88,   88,   303, 283,  334, 0,
        240, 154,  149,  262, 0,    265, 263, 153,  270, 1457, 19,   19,   255, 175,  275, 427,
        271, 201,  242,  321, 265,  0,   342, 239,  631, 285,  68,   68,   277, 511,  299, 363,
        318, 250,  257,  355, 263,  342, 0,   253,  881, 0,    80,   80,   318, 271,  337, 378,
        210, 168,  1410, 573, 153,  239, 253, 0,    230, 203,  41,   41,   212, 194,  233, 223,
        270, 230,  230,  308, 270,  631, 881, 230,  0,   303,  65,   65,   259, 0,    293, 348,
        271, 198,  199,  313, 1457, 285, 0,   203,  303, 0,    30,   30,   289, 217,  296, 292,
        71,  50,   45,   88,  19,   68,  80,  41,   65,  30,   0,    3541, 67,  45,   73,  100,
        71,  50,   45,   88,  19,   68,  80,  41,   65,  30,   3541, 0,    67,  45,   73,  100,
        749, 220,  211,  303, 255,  277, 318, 212,  259, 289,  67,   67,   0,   229,  601, 326,
        222, 1493, 189,  283, 175,  511, 271, 194,  0,   217,  45,   45,   229, 0,    224, 285,
        264, 478,  233,  334, 275,  299, 337, 233,  293, 296,  73,   73,   601, 224,  0,   370,
        337, 258,  576,  0,   427,  363, 378, 223,  348, 292,  100,  100,  326, 285,  370, 0,
    }, game.probabilities);

    // Episode 5 – truth booth – Danny + Jenna = no match
    try game.applyTruthBooth(4, 6, false);
    try std.testing.expectEqual(4120, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,   204,  207,  638, 240,  247, 318, 203,  232, 249,  71,   71,   665, 214,  242, 319,
        204, 0,    150,  252, 154,  188, 250, 161,  216, 182,  50,   50,   209, 1376, 434, 244,
        207, 150,  0,    215, 149,  226, 257, 1307, 215, 181,  45,   45,   199, 183,  215, 526,
        638, 252,  215,  0,   262,  294, 355, 523,  272, 288,  88,   88,   276, 263,  306, 0,
        240, 154,  149,  262, 0,    265, 0,   153,  270, 1457, 19,   19,   255, 175,  275, 427,
        247, 188,  226,  294, 265,  0,   342, 224,  609, 260,  68,   68,   252, 472,  270, 335,
        318, 250,  257,  355, 0,    342, 0,   253,  881, 0,    80,   80,   318, 271,  337, 378,
        203, 161,  1307, 523, 153,  224, 253, 0,    217, 185,  41,   41,   202, 187,  216, 207,
        232, 216,  215,  272, 270,  609, 881, 217,  0,   273,  65,   65,   234, 0,    256, 315,
        249, 182,  181,  288, 1457, 260, 0,   185,  273, 0,    28,   28,   259, 197,  269, 264,
        71,  50,   45,   88,  19,   68,  80,  41,   65,  28,   0,    3282, 66,  45,   73,  99,
        71,  50,   45,   88,  19,   68,  80,  41,   65,  28,   3282, 0,    66,  45,   73,  99,
        665, 209,  199,  276, 255,  252, 318, 202,  234, 259,  66,   66,   0,   217,  601, 301,
        214, 1376, 183,  263, 175,  472, 271, 187,  0,   197,  45,   45,   217, 0,    211, 264,
        242, 434,  215,  306, 275,  270, 337, 216,  256, 269,  73,   73,   601, 211,  0,   342,
        319, 244,  526,  0,   427,  335, 378, 207,  315, 264,  99,   99,   301, 264,  342, 0,
    }, game.probabilities);

    // Episode 5 – matchup – 1 beam
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
    try std.testing.expectEqual(1577, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,   42,  102, 199, 105, 101, 141, 90,  81,  105, 34,   34,   293, 38,  36,  176,
        42,  0,   41,  50,  43,  43,  68,  37,  43,  55,  9,    10,   44,  919, 124, 49,
        102, 41,  0,   99,  27,  113, 135, 323, 77,  89,  33,   35,   71,  49,  113, 270,
        199, 50,  99,  0,   121, 135, 137, 290, 84,  119, 41,   42,   86,  51,  123, 0,
        105, 43,  27,  121, 0,   142, 0,   80,  116, 479, 16,   12,   104, 45,  148, 139,
        101, 43,  113, 135, 142, 0,   43,  111, 196, 125, 39,   42,   96,  143, 128, 120,
        141, 68,  135, 137, 0,   43,  0,   129, 378, 0,   41,   43,   123, 71,  137, 131,
        90,  37,  323, 290, 80,  111, 129, 0,   74,  77,  31,   1,    75,  44,  112, 103,
        81,  43,  77,  84,  116, 196, 378, 74,  0,   102, 29,   30,   177, 0,   86,  104,
        105, 55,  89,  119, 479, 125, 0,   77,  102, 0,   5,    21,   95,  55,  133, 117,
        34,  9,   33,  41,  16,  39,  41,  31,  29,  5,   0,    1177, 31,  10,  37,  44,
        34,  10,  35,  42,  12,  42,  43,  1,   30,  21,  1177, 0,    34,  10,  39,  47,
        293, 44,  71,  86,  104, 96,  123, 75,  177, 95,  31,   34,   0,   45,  201, 102,
        38,  919, 49,  51,  45,  143, 71,  44,  0,   55,  10,   10,   45,  0,   41,  56,
        36,  124, 113, 123, 148, 128, 137, 112, 86,  133, 37,   39,   201, 41,  0,   119,
        176, 49,  270, 0,   139, 120, 131, 103, 104, 117, 44,   47,   102, 56,  119, 0,
    }, game.probabilities);

    // Episode 6 – Kari + Kylie = no match
    try game.applyTruthBooth(10, 11, false);
    try std.testing.expectEqual(400, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,  2,   19,  89,  1,   17,  28,  18,  14,  4,   34, 34, 94,  2,   16,  28,
        2,  0,   0,   7,   0,   2,   2,   0,   5,   0,   9,  10, 3,   331, 23,  6,
        19, 0,   0,   16,  0,   21,  18,  109, 9,   4,   33, 35, 16,  0,   24,  96,
        89, 7,   16,  0,   9,   8,   25,  103, 11,  12,  41, 42, 10,  7,   20,  0,
        1,  0,   0,   9,   0,   8,   0,   0,   1,   316, 16, 12, 1,   0,   7,   29,
        17, 2,   21,  8,   8,   0,   19,  24,  119, 10,  39, 42, 14,  32,  18,  27,
        28, 2,   18,  25,  0,   19,  0,   24,  136, 0,   41, 43, 22,  2,   18,  22,
        18, 0,   109, 103, 0,   24,  24,  0,   12,  0,   31, 1,  20,  0,   30,  28,
        14, 5,   9,   11,  1,   119, 136, 12,  0,   4,   29, 30, 9,   0,   9,   12,
        4,  0,   4,   12,  316, 10,  0,   0,   4,   0,   5,  21, 4,   0,   8,   12,
        34, 9,   33,  41,  16,  39,  41,  31,  29,  5,   0,  0,  31,  10,  37,  44,
        34, 10,  35,  42,  12,  42,  43,  1,   30,  21,  0,  0,  34,  10,  39,  47,
        94, 3,   16,  10,  1,   14,  22,  20,  9,   4,   31, 34, 0,   2,   123, 17,
        2,  331, 0,   7,   0,   32,  2,   0,   0,   0,   10, 10, 2,   0,   0,   4,
        16, 23,  24,  20,  7,   18,  18,  30,  9,   8,   37, 39, 123, 0,   0,   28,
        28, 6,   96,  0,   29,  27,  22,  28,  12,  12,  44, 47, 17,  4,   28,  0,
    }, game.probabilities);

    // Episode 6 – matchup – blackout
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
    try std.testing.expectEqual(55, game.numRemainingScenarios());
    try std.testing.expectEqualSlices(u64, &.{
        0,  2,  0,  11, 0,  0,  1,  0,  0,  0,  3, 3, 10, 2,  2,  21,
        2,  0,  0,  6,  0,  2,  2,  0,  3,  0,  8, 9, 3,  0,  14, 6,
        0,  0,  0,  0,  0,  0,  0,  55, 0,  0,  0, 0, 0,  0,  0,  0,
        11, 6,  0,  0,  0,  8,  5,  0,  2,  1,  7, 9, 0,  6,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  47, 0, 1, 0,  0,  0,  7,
        0,  2,  0,  8,  0,  0,  2,  0,  16, 0,  2, 2, 0,  23, 0,  0,
        1,  2,  0,  5,  0,  2,  0,  0,  16, 0,  7, 0, 2,  2,  18, 0,
        0,  0,  55, 0,  0,  0,  0,  0,  0,  0,  0, 0, 0,  0,  0,  0,
        0,  3,  0,  2,  0,  16, 16, 0,  0,  0,  5, 7, 4,  0,  0,  2,
        0,  0,  0,  1,  47, 0,  0,  0,  0,  0,  4, 2, 0,  0,  0,  1,
        3,  8,  0,  7,  0,  2,  7,  0,  5,  4,  0, 0, 5,  8,  0,  6,
        3,  9,  0,  9,  1,  2,  0,  0,  7,  2,  0, 0, 7,  9,  0,  6,
        10, 3,  0,  0,  0,  0,  2,  0,  4,  0,  5, 7, 0,  1,  21, 2,
        2,  0,  0,  6,  0,  23, 2,  0,  0,  0,  8, 9, 1,  0,  0,  4,
        2,  14, 0,  0,  0,  0,  18, 0,  0,  0,  0, 0, 21, 0,  0,  0,
        21, 6,  0,  0,  7,  0,  0,  0,  2,  1,  6, 6, 2,  4,  0,  0,
    }, game.probabilities);

    // Jasmine = 5 and Nour = 13 have 41.82% of match which makes then the
    // optimal next truth booth. The order doesn't matter here as this is
    // bisexual mode.
    const optimalTruthBooth = game.findOptimalTruthBooth();
    _ = std.mem.eql(usize, &.{ 5, 13 }, &optimalTruthBooth);
    try std.testing.expectEqual(optimalTruthBooth.len, 2);
    try std.testing.expect((optimalTruthBooth[0] == 5 and optimalTruthBooth[1] == 13) or (optimalTruthBooth[0] == 13 and optimalTruthBooth[1] == 5));

    // The season continues for another 6 episodes, but my reference material
    // does not do the full calculations of the probabilities, so I cannot be
    // sure that my calculations are correct.
}
