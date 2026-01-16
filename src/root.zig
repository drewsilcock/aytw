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
    m: u32,
    mode: GameMode,
    names: std.ArrayList([]const u8),
    eliminated: std.bit_set.DynamicBitSetUnmanaged,
    num_total_scenarios: usize,
    num_remaining_scenarios: usize,
    probabilities: std.ArrayList(u64),
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new game instance.
    /// n = number of contestants
    pub fn init(allocator: std.mem.Allocator, n: u32, options: GameOptions) !Self {
        if (n % 2 != 0) {
            return error.InvalidNumberOfContestants;
        }

        const m = n / 2;

        var names = try std.ArrayList([]const u8).initCapacity(allocator, n);
        errdefer names.deinit(allocator);

        if (options.names) |input_names| {
            if (input_names.len != n) {
                return error.InvalidNumberOfNames;
            }

            // Assume that user has put the male names first and the female names last.
            names.appendSliceAssumeCapacity(input_names);
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

            names.appendSliceAssumeCapacity(male_names[0..m]);
            names.appendSliceAssumeCapacity(female_names[0..m]);
        }

        const num_scenarios = switch (options.mode) {
            .standard => maths.factorial(m),
            .bisexual => maths.factorial(n) / (try std.math.powi(u32, 2, m) * maths.factorial(m)),
        };

        const num_possibilities = switch (options.mode) {
            // In standard, each male could match w/ each female.
            .standard => m * m,
            // In bisexual, each person can match w/ anyone else apart from themselves.
            .bisexual => n * (n - 1),
        };

        // Instead of storing the normalised probabilities, we store the n#
        // scenarios that are compatible with the given pairing; to get the
        // probability, simple divide this value by num_remaining_scenarios.
        var probabilities = try std.ArrayList(u64).initCapacity(allocator, num_possibilities);
        errdefer probabilities.deinit(allocator);

        const starting_num_poss = switch (options.mode) {
            // In standard, each male can match with each female giving
            // probability 1/M for each.
            .standard => num_scenarios / m,
            // In bisexual, each person can match with any other person apart
            // from themselves, giving N-1 possibilities and so probability
            // 1/(N-1).
            .bisexual => num_scenarios / (n - 1),
        };

        for (0..num_possibilities) |_| {
            probabilities.appendAssumeCapacity(starting_num_poss);
        }

        var eliminated = try std.bit_set.DynamicBitSetUnmanaged.initEmpty(allocator, num_scenarios);
        errdefer eliminated.deinit(allocator);

        return Self{
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
        self.names.deinit(self.allocator);
        self.eliminated.deinit(self.allocator);
        self.probabilities.deinit(self.allocator);
    }

    pub fn numRemainingScenarios(self: Self) u64 {
        return self.num_remaining_scenarios;
    }

    pub fn applyMatchup(self: *Self, matchup: []const u32, num_correct: u8) !void {
        for (self.probabilities.items) |*item| {
            item.* = 0;
        }

        const perm = try self.allocator.alloc(u32, self.m);
        defer self.allocator.free(perm);

        for (0..self.num_total_scenarios) |k| {
            if (self.eliminated.isSet(k)) {
                continue;
            }

            switch (self.mode) {
                .standard => try self.getScenarioStandard(k, perm),
                .bisexual => try self.getScenarioBisexual(k, perm),
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
                self.probabilities.items[prob_idx] += 1;
            }
        }
    }

    pub fn applyTruthBooth(self: *Self, male_idx: usize, female_idx: usize, is_match: bool) !void {
        for (self.probabilities.items) |*item| {
            item.* = 0;
        }

        const perm = try self.allocator.alloc(u32, self.m);
        defer self.allocator.free(perm);

        for (0..self.num_total_scenarios) |k| {
            if (self.eliminated.isSet(k)) {
                continue;
            }

            switch (self.mode) {
                .standard => try self.getScenarioStandard(k, perm),
                .bisexual => try self.getScenarioBisexual(k, perm),
            }

            if ((perm[male_idx] == female_idx) != is_match) {
                self.eliminated.set(k);
                self.num_remaining_scenarios -= 1;
                continue;
            }

            // TODO: This works differently in bisexual mode.
            for (0..perm.len) |i| {
                const j = perm[i];
                const prob_idx = i * self.m + j;
                self.probabilities.items[prob_idx] += 1;
            }
        }
    }

    pub fn printProbabilities(self: *const Self) !void {
        var table = Table.init(self.allocator);
        defer table.deinit();

        var row = try std.ArrayList([]const u8).initCapacity(self.allocator, self.m + 1);
        defer row.deinit(self.allocator);

        row.appendAssumeCapacity("");
        row.appendSliceAssumeCapacity(self.names.items[self.m .. self.m * 2]);
        try table.setTitle(row.items);
        row.clearRetainingCapacity();

        var printBuf: [1024]u8 = undefined;
        var bufIdx: usize = 0;

        // i = male index, j = female index
        for (0..self.m) |i| {
            row.appendAssumeCapacity(self.names.items[i]);
            for (0..self.m) |j| {
                const num_poss = self.probabilities.items[i * self.m + j];
                const prob = @as(f32, @floatFromInt(num_poss)) / @as(f32, @floatFromInt(self.num_remaining_scenarios));
                const text = try std.fmt.bufPrint(printBuf[bufIdx..], "{d: >6.2}%", .{prob * 100});
                bufIdx += text.len;
                row.appendAssumeCapacity(text);
            }
            try table.addRow(row.items);
            row.clearRetainingCapacity();
        }

        try table.print_tty(false);
    }

    fn getScenarioStandard(self: *const Self, k: usize, out: []u32) !void {
        try maths.getPermutation(self.m, k, out);
    }

    fn getScenarioBisexual(self: *const Self, k: usize, out: []u32) !void {
        _ = out; // autofix
        _ = k; // autofix
        _ = self; // autofix
        // TODO: Is there a variant of Lehmer coding for unordered pairs of
        // items from a list of length N?
        return error.NotImplemented;
    }

    fn freeScenario(self: *const Self, scenario: []u32) void {
        self.allocator.free(scenario);
    }
};
