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
    probabilities: []u64,
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
        @memset(self.probabilities, 0);

        const size = switch (self.mode) {
            .standard => self.m,
            .bisexual => self.n,
        };

        const perm = try self.allocator.alloc(u32, size);
        defer self.allocator.free(perm);

        // Available array only needed for bisexual permutation generation, not standard mode.
        var available: []bool = undefined;
        if (self.mode == .bisexual) {
            available = try self.allocator.alloc(bool, size);
            defer self.allocator.free(available);
        }

        for (0..self.num_total_scenarios) |k| {
            if (self.eliminated.isSet(k)) {
                continue;
            }

            switch (self.mode) {
                .standard => self.getScenarioStandard(k, perm),
                .bisexual => self.getScenarioBisexual(k, available, perm),
            }

            const num_matches = maths.countMatching(u32, perm, matchup);
            if (num_matches != num_correct) {
                self.eliminated.set(k);
                self.num_remaining_scenarios -= 1;
                continue;
            }

            // TODO: This works differently in bisexual mode.
            for (0..perm.len) |i| {
                const j = perm[i];
                const prob_idx = i * self.m + j;
                self.probabilities[prob_idx] += 1;
            }
        }
    }

    pub fn applyTruthBooth(self: *Self, idx1: usize, idx2: usize, is_match: bool) !void {
        // For standard mode, idx1 = male, idx2 = female
        // For bisexual mode, idx1 = row, idx2 = column
        @memset(self.probabilities, 0);

        const size = switch (self.mode) {
            .standard => self.m,
            .bisexual => self.n,
        };

        const perm = try self.allocator.alloc(u32, size);
        defer self.allocator.free(perm);

        // Available array only needed for bisexual permutation generation, not standard mode.
        var available: []bool = undefined;
        if (self.mode == .bisexual) {
            available = try self.allocator.alloc(bool, size);
            defer self.allocator.free(available);
        }

        for (0..self.num_total_scenarios) |k| {

            // Instead of keeping bitmask for every iteration, could we keep
            // array of remaining indices? That way, we only iterate through the
            // remaining possibilities, potentially saving time.
            if (self.eliminated.isSet(k)) {
                continue;
            }

            std.debug.print("Generating {d}/{d} permutation/pairing\n", .{ k, self.num_total_scenarios });
            switch (self.mode) {
                .standard => self.getScenarioStandard(k, perm),
                .bisexual => self.getScenarioBisexual(k, available, perm),
            }
            std.debug.print("Processed {d}/{d} scenarios\n", .{ k, self.num_total_scenarios });

            if ((perm[idx1] == idx2) != is_match) {
                self.eliminated.set(k);
                self.num_remaining_scenarios -= 1;
                continue;
            }

            for (0..perm.len) |i| {
                const j = perm[i];
                const prob_idx = i * self.m + j;
                self.probabilities[prob_idx] += 1;
            }
        }
    }

    pub fn printProbabilities(self: *const Self) !void {
        var table = Table.init(self.allocator);
        defer table.deinit();

        const row_size = switch (self.mode) {
            .standard => self.m + 1,
            .bisexual => self.n + 1,
        };
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

        // The logic here is fundamentally different for standard and bisexual modes.
        switch (self.mode) {
            .standard => {
                // i = male index, j = female index
                for (0..self.m) |i| {
                    row[0] = self.names[i];
                    for (0..self.m) |j| {
                        const num_poss = self.probabilities[i * self.m + j];
                        const prob = @as(f32, @floatFromInt(num_poss)) / @as(f32, @floatFromInt(self.num_remaining_scenarios));
                        const text = try std.fmt.bufPrint(printBuf[bufIdx..], "{d: >6.2}%", .{prob * 100});
                        bufIdx += text.len;
                        row[j + 1] = text;
                    }
                    try table.addRow(row);
                }
            },
            .bisexual => {
                // k1 = index into all names (row-index)
                // k2 = index into all names (column-index)
                for (0..self.n) |k1| {
                    row[0] = self.names[k1];
                    for (0..self.n) |k2| {
                        const num_poss = self.probabilities[k1 * self.n + k2];
                        const prob = @as(f32, @floatFromInt(num_poss)) / @as(f32, @floatFromInt(self.num_remaining_scenarios));
                        const text = try std.fmt.bufPrint(printBuf[bufIdx..], "{d: >6.2}%", .{prob * 100});
                        bufIdx += text.len;
                        row[k2 + 1] = text;
                    }
                    try table.addRow(row);
                }
            },
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
