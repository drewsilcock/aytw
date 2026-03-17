const std = @import("std");
const aytw = @import("aytw");

pub const TruthBoothEvent = struct {
    idx1: usize,
    idx2: usize,
    is_match: bool,
};

pub const MatchupEvent = struct {
    matchup: []const u32,
    num_correct: u8,
};

pub const Event = union(enum) {
    truth_booth: TruthBoothEvent,
    matchup: MatchupEvent,
};

pub const Season = struct {
    name: []const u8,
    n: u32,
    mode: aytw.GameMode,
    names: []const []const u8,
    events: []const Event,
};

pub const demo_standard_3 = Season{
    .name = "Demo Standard 3",
    .n = 6,
    .mode = .standard,
    .names = &.{ "Albert", "Bill", "Carl", "Daisy", "Emily", "Faith" },
    .events = &.{
        .{ .truth_booth = .{ .idx1 = 0, .idx2 = 0, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 1, 0, 2 }, .num_correct = 1 } },
    },
};

pub const demo_standard_11 = Season{
    .name = "Demo Standard 11",
    .n = 22,
    .mode = .standard,
    .names = &.{
        "Al",     "Bob",   "Chuck", "Dale",  "Evan",
        "Frank",  "Graham","Hugh",  "Ike",   "James",
        "Kirk",   "Lauren","Mandy", "Nora",  "Olivia",
        "Pam",    "Quinn", "Riley", "Sam",   "Tara",
        "Uma",    "Violet",
    },
    .events = &.{
        .{ .truth_booth = .{ .idx1 = 0, .idx2 = 1, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 2, 1, 3, 0, 4, 5, 6, 5, 8, 9, 10 }, .num_correct = 3 } },
    },
};

pub const demo_bisexual_6 = Season{
    .name = "Demo Bisexual 6",
    .n = 6,
    .mode = .bisexual,
    .names = &.{ "Albert", "Bill", "Carl", "Daisy", "Emily", "Faith" },
    .events = &.{
        .{ .truth_booth = .{ .idx1 = 0, .idx2 = 3, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 4, 3, 5, 1, 0, 2 }, .num_correct = 1 } },
    },
};

pub const season_8 = Season{
    .name = "Season 8",
    .n = 16,
    .mode = .bisexual,
    .names = &.{
        "Aasha",    "Amber",    "Basit",    "Brandon",
        "Danny",    "Jasmine",  "Jenna",    "Jonathan",
        "Justin",   "Kai",      "Kari",     "Kylie",
        "Max",      "Nour",     "Paige",    "Remy",
    },
    .events = &.{
        .{ .truth_booth = .{ .idx1 = 8, .idx2 = 13, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 14, 13, 7, 15, 9, 6, 5, 2, 12, 4, 11, 10, 8, 1, 0, 3 }, .num_correct = 2 } },
        .{ .truth_booth = .{ .idx1 = 3, .idx2 = 15, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 3, 13, 7, 0, 15, 8, 9, 2, 5, 6, 11, 10, 14, 1, 12, 4 }, .num_correct = 2 } },
        .{ .truth_booth = .{ .idx1 = 6, .idx2 = 9, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 12, 14, 15, 7, 9, 13, 8, 3, 6, 4, 11, 10, 0, 5, 1, 2 }, .num_correct = 2 } },
        .{ .truth_booth = .{ .idx1 = 4, .idx2 = 6, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 15, 13, 4, 5, 2, 3, 14, 11, 12, 10, 9, 7, 8, 1, 6, 0 }, .num_correct = 1 } },
        .{ .truth_booth = .{ .idx1 = 10, .idx2 = 11, .is_match = false } },
        .{ .matchup = .{ .matchup = &.{ 9, 13, 15, 12, 10, 14, 11, 8, 7, 0, 4, 6, 3, 1, 5, 2 }, .num_correct = 0 } },
    },
};

pub const all_seasons = std.StaticStringMap(*const Season).initComptime(&.{
    .{ "demo-standard-3",  &demo_standard_3 },
    .{ "demo-standard-11", &demo_standard_11 },
    .{ "demo-bisexual-6",  &demo_bisexual_6 },
    .{ "season-8",         &season_8 },
});

fn validateSeason(season: *const Season) !void {
    try std.testing.expectEqual(@as(usize, season.n), season.names.len);

    for (season.events) |event| {
        switch (event) {
            .matchup => |mu| {
                switch (season.mode) {
                    .standard => {
                        const m = season.n / 2;
                        try std.testing.expectEqual(@as(usize, m), mu.matchup.len);
                        var seen = [_]bool{false} ** 32;
                        for (mu.matchup) |fi| {
                            try std.testing.expect(fi < m);
                            try std.testing.expect(!seen[fi]);
                            seen[fi] = true;
                        }
                    },
                    .bisexual => {
                        try std.testing.expectEqual(@as(usize, season.n), mu.matchup.len);
                        for (mu.matchup, 0..) |partner, i| {
                            try std.testing.expect(partner != i);
                            try std.testing.expectEqual(i, mu.matchup[partner]);
                        }
                    },
                }
            },
            .truth_booth => {},
        }
    }
}

test "season data integrity: demo-standard-3" {
    try validateSeason(&demo_standard_3);
}

test "season data integrity: demo-bisexual-6" {
    try validateSeason(&demo_bisexual_6);
}

test "season data integrity: season-8" {
    try validateSeason(&season_8);
}
