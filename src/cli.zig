const std = @import("std");

const aytw = @import("aytw");
const seasons = @import("seasons");

pub const PauseContext = enum { replay, play_truth_booth, play_matchup };

pub const PauseAction = union(enum) {
    continue_game,
    quit,
    enter_truth_booth,
    enter_matchup,
};

fn printScenarioCount(game: *const aytw.Game) void {
    std.debug.print("--- {d}/{d} scenarios remaining ---\n", .{
        game.numRemainingScenarios(),
        game.num_total_scenarios,
    });
}

fn readLine(allocator: std.mem.Allocator) ![]u8 {
    var line = try std.fs.File.stdin().deprecatedReader().readUntilDelimiterAlloc(allocator, '\n', 4096);
    if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
    return line;
}

fn readU32(allocator: std.mem.Allocator) !u32 {
    const line = try readLine(allocator);
    defer allocator.free(line);
    return std.fmt.parseInt(u32, std.mem.trim(u8, line, " \t"), 10);
}

fn resolveName(names: []const []const u8, input: []const u8) ?usize {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (std.fmt.parseInt(usize, trimmed, 10) catch null) |idx| {
        if (idx < names.len) return idx;
    }
    for (names, 0..) |name, i| {
        if (std.ascii.eqlIgnoreCase(name, trimmed)) return i;
    }
    return null;
}

fn hintAllocation(num_scenarios: usize) u8 {
    if (num_scenarios > 1_000_000) return 2;
    if (num_scenarios > 500_000) return 1;
    return 0;
}

pub fn pauseMenu(
    game: *aytw.Game,
    context: PauseContext,
    hints_remaining: *u8,
    prize: ?*u32,
    allocator: std.mem.Allocator,
) !PauseAction {
    while (true) {
        printScenarioCount(game);
        std.debug.print("Options:\n", .{});
        std.debug.print("  [p] Print probabilities\n", .{});
        switch (context) {
            .replay => {
                std.debug.print("  [t] Optimal truth booth\n", .{});
                std.debug.print("  [m] Optimal matchup\n", .{});
                std.debug.print("  [c] Continue\n", .{});
            },
            .play_truth_booth => {
                std.debug.print("  [b] Enter truth booth\n", .{});
                if (hints_remaining.* > 0) {
                    std.debug.print("  [h] Use hint ({d} remaining, costs 250k sedges)\n", .{hints_remaining.*});
                }
            },
            .play_matchup => {
                std.debug.print("  [u] Enter matchup ceremony\n", .{});
                if (hints_remaining.* > 0) {
                    std.debug.print("  [h] Use hint ({d} remaining, costs 250k sedges)\n", .{hints_remaining.*});
                }
            },
        }
        std.debug.print("  [q] Quit\n", .{});
        std.debug.print("> ", .{});

        const line = readLine(allocator) catch |err| {
            if (err == error.EndOfStream) return .quit;
            return err;
        };
        defer allocator.free(line);

        if (line.len == 0) continue;
        switch (line[0]) {
            'p' => try game.printProbabilities(),
            't' => if (context == .replay) {
                const result = game.findOptimalTruthBooth();
                std.debug.print("Optimal truth booth: ({s}, {s}), entropy = {d:.4} Sh\n", .{
                    game.names[result.pair[0]],
                    game.names[result.pair[1]],
                    result.entropy,
                });
            } else {
                std.debug.print("Unknown option '{c}'. Try again.\n", .{line[0]});
            },
            'm' => if (context == .replay) {
                std.debug.print("Computing optimal matchup...\n", .{});
                const size = if (game.mode == .standard) game.m else game.n;
                const matchup = try allocator.alloc(u32, size);
                defer allocator.free(matchup);
                const entropy = try game.findOptimalMatchup(matchup);
                var buf: [4096]u8 = undefined;
                const s = try game.matchupToString(matchup, &buf);
                std.debug.print("Optimal matchup: {s}, entropy = {d:.4} Sh\n", .{ s, entropy });
            } else {
                std.debug.print("Unknown option '{c}'. Try again.\n", .{line[0]});
            },
            'b' => if (context == .play_truth_booth) return .enter_truth_booth,
            'u' => if (context == .play_matchup) return .enter_matchup,
            'h' => if (context == .play_truth_booth or context == .play_matchup) {
                if (hints_remaining.* > 0) {
                    hints_remaining.* -= 1;
                    if (prize) |p| {
                        p.* = if (p.* >= 250_000) p.* - 250_000 else 0;
                        std.debug.print("Prize reduced to {d} sedges.\n", .{p.*});
                    }
                    const result = game.findOptimalTruthBooth();
                    std.debug.print("Hint: optimal truth booth is ({s}, {s}), entropy = {d:.4} Sh\n", .{
                        game.names[result.pair[0]],
                        game.names[result.pair[1]],
                        result.entropy,
                    });
                } else {
                    std.debug.print("No hints remaining.\n", .{});
                }
            },
            'c' => if (context == .replay) return .continue_game,
            'q' => return .quit,
            else => std.debug.print("Unknown option '{c}'. Try again.\n", .{line[0]}),
        }
    }
}

fn printContestants(game: *const aytw.Game) void {
    for (game.names, 0..) |name, i| {
        std.debug.print("  {d}: {s}\n", .{ i, name });
    }
}

fn promptTruthBooth(game: *aytw.Game, answer_key: []const u32, allocator: std.mem.Allocator) !void {
    if (game.mode == .standard) {
        std.debug.print("Males:\n", .{});
        for (game.names[0..game.m], 0..) |name, i| {
            std.debug.print("  {d}: {s}\n", .{ i, name });
        }
        std.debug.print("Females:\n", .{});
        for (game.names[game.m..], 0..) |name, i| {
            std.debug.print("  {d}: {s}\n", .{ i, name });
        }
    } else {
        std.debug.print("Contestants:\n", .{});
        printContestants(game);
    }

    const idx1 = blk: {
        const names = if (game.mode == .standard) game.names[0..game.m] else game.names;
        const label = if (game.mode == .standard) "male" else "contestant #1";
        while (true) {
            std.debug.print("Enter {s} (name or index): ", .{label});
            const line = try readLine(allocator);
            defer allocator.free(line);
            if (resolveName(names, line)) |idx| break :blk idx;
            std.debug.print("Not found. Try again.\n", .{});
        }
    };

    const idx2 = blk: {
        const names = if (game.mode == .standard) game.names[game.m..] else game.names;
        const label = if (game.mode == .standard) "female" else "contestant #2";
        while (true) {
            std.debug.print("Enter {s} (name or index): ", .{label});
            const line = try readLine(allocator);
            defer allocator.free(line);
            if (resolveName(names, line)) |idx| {
                if (game.mode == .bisexual and idx == idx1) {
                    std.debug.print("Must pick a different contestant.\n", .{});
                    continue;
                }
                break :blk idx;
            }
            std.debug.print("Not found. Try again.\n", .{});
        }
    };

    const is_match = answer_key[idx1] == idx2;
    const name1 = if (game.mode == .standard) game.names[idx1] else game.names[idx1];
    const name2 = if (game.mode == .standard) game.names[game.m + idx2] else game.names[idx2];
    std.debug.print("Truth booth result: {s} + {s} — {s}\n", .{
        name1,
        name2,
        if (is_match) "MATCH" else "NO MATCH",
    });
    try game.applyTruthBooth(idx1, idx2, is_match);
}

fn promptMatchupStandard(game: *aytw.Game, matchup: []u32, allocator: std.mem.Allocator) !void {
    std.debug.print("Females:\n", .{});
    for (game.names[game.m..], 0..) |name, i| {
        std.debug.print("  {d}: {s}\n", .{ i, name });
    }

    var used = try allocator.alloc(bool, game.m);
    defer allocator.free(used);
    @memset(used, false);

    for (0..game.m) |i| {
        while (true) {
            std.debug.print("{s} is paired with (female name or index): ", .{game.names[i]});
            const line = try readLine(allocator);
            defer allocator.free(line);
            if (resolveName(game.names[game.m..], line)) |fi| {
                if (used[fi]) {
                    std.debug.print("{s} already used. Pick another.\n", .{game.names[game.m + fi]});
                    continue;
                }
                matchup[i] = @intCast(fi);
                used[fi] = true;
                break;
            }
            std.debug.print("Not found. Try again.\n", .{});
        }
    }
}

fn promptMatchupBisexual(game: *aytw.Game, matchup: []u32, allocator: std.mem.Allocator) !void {
    std.debug.print("Contestants:\n", .{});
    printContestants(game);

    @memset(matchup, std.math.maxInt(u32));

    var paired = try allocator.alloc(bool, game.n);
    defer allocator.free(paired);
    @memset(paired, false);

    var pair_num: usize = 0;
    while (pair_num < game.n / 2) {
        std.debug.print("Pair {d} (e.g. \"Aasha Kai\"): ", .{pair_num + 1});
        const line = try readLine(allocator);
        defer allocator.free(line);

        const trimmed = std.mem.trim(u8, line, " \t");
        const space = std.mem.indexOf(u8, trimmed, " ") orelse {
            std.debug.print("Enter two names separated by a space.\n", .{});
            continue;
        };
        const part1 = trimmed[0..space];
        const part2 = std.mem.trim(u8, trimmed[space + 1 ..], " \t");

        const idx1 = resolveName(game.names, part1) orelse {
            std.debug.print("'{s}' not found. Try again.\n", .{part1});
            continue;
        };
        const idx2 = resolveName(game.names, part2) orelse {
            std.debug.print("'{s}' not found. Try again.\n", .{part2});
            continue;
        };
        if (idx1 == idx2) {
            std.debug.print("Must pair two different contestants.\n", .{});
            continue;
        }
        if (paired[idx1] or paired[idx2]) {
            std.debug.print("One or both contestants already paired.\n", .{});
            continue;
        }
        matchup[idx1] = @intCast(idx2);
        matchup[idx2] = @intCast(idx1);
        paired[idx1] = true;
        paired[idx2] = true;
        pair_num += 1;
    }
}

fn promptMatchup(game: *aytw.Game, answer_key: []const u32, allocator: std.mem.Allocator) !u32 {
    const size = if (game.mode == .standard) game.m else game.n;
    const matchup = try allocator.alloc(u32, size);
    defer allocator.free(matchup);

    if (game.mode == .standard) {
        try promptMatchupStandard(game, matchup, allocator);
    } else {
        try promptMatchupBisexual(game, matchup, allocator);
    }

    const beams = game.beamsForMatchup(matchup, answer_key);
    std.debug.print("Matchup result: {d} beam(s)\n", .{beams});
    try game.applyMatchup(matchup, @intCast(beams));
    return beams;
}

pub fn runReplay(season: *const seasons.Season, allocator: std.mem.Allocator) !void {
    var game = try aytw.Game.init(allocator, season.n, .{
        .mode = season.mode,
        .names = season.names,
    });
    defer game.deinit();

    std.debug.print("Replaying {s} — {d} contestants, {d} initial scenarios\n", .{
        season.name,
        season.n,
        game.numRemainingScenarios(),
    });

    var hints: u8 = 0;
    var action = try pauseMenu(&game, .replay, &hints, null, allocator);
    if (action == .quit) return;

    for (season.events, 0..) |event, i| {
        switch (event) {
            .truth_booth => |tb| {
                std.debug.print("\nEvent {d}: Truth booth — {s} + {s} = {s}\n", .{
                    i + 1,
                    game.names[if (game.mode == .standard) tb.idx1 else tb.idx1],
                    if (game.mode == .standard) game.names[game.m + tb.idx2] else game.names[tb.idx2],
                    if (tb.is_match) "MATCH" else "no match",
                });
                try game.applyTruthBooth(tb.idx1, tb.idx2, tb.is_match);
            },
            .matchup => |mu| {
                var buf: [4096]u8 = undefined;
                const s = try game.matchupToString(mu.matchup, &buf);
                std.debug.print("\nEvent {d}: Matchup — {s} = {d} beam(s)\n", .{
                    i + 1,
                    s,
                    mu.num_correct,
                });
                try game.applyMatchup(mu.matchup, mu.num_correct);
            },
        }
        action = try pauseMenu(&game, .replay, &hints, null, allocator);
        if (action == .quit) return;
    }

    std.debug.print("\nEnd of replay.\n", .{});
}

pub fn runPlay(allocator: std.mem.Allocator) !void {
    const stdin = std.fs.File.stdin().deprecatedReader();

    std.debug.print("Choose mode:\n  [s] Standard (male/female pairs) [default]\n  [b] Bisexual\n> ", .{});
    const mode_line = try stdin.readUntilDelimiterAlloc(allocator, '\n', 64);
    defer allocator.free(mode_line);
    const mode: aytw.GameMode = if (mode_line.len > 0 and mode_line[0] == 'b') .bisexual else .standard;

    const n: u32 = blk: {
        while (true) {
            std.debug.print("Number of contestants (must be even): ", .{});
            const n = readU32(allocator) catch {
                std.debug.print("Invalid number. Try again.\n", .{});
                continue;
            };
            if (n < 2 or n % 2 != 0) {
                std.debug.print("Must be even and at least 2. Try again.\n", .{});
                continue;
            }
            break :blk n;
        }
    };

    std.debug.print("Provide custom names? [y/N]: ", .{});
    const names_line = try std.fs.File.stdin().deprecatedReader().readUntilDelimiterAlloc(allocator, '\n', 64);
    defer allocator.free(names_line);
    const custom_names = names_line.len > 0 and (names_line[0] == 'y' or names_line[0] == 'Y');

    var provided_names: ?[][]const u8 = null;
    var name_bufs: ?[][]u8 = null;
    if (custom_names) {
        const name_slice = try allocator.alloc([]const u8, n);
        const buf_slice = try allocator.alloc([]u8, n);
        for (0..n) |i| {
            const label = switch (game_mode_label(mode, i, n)) {
                .male => "male",
                .female => "female",
                .contestant => "contestant",
            };
            std.debug.print("Name for {s} {d}: ", .{ label, i });
            const name_line = try std.fs.File.stdin().deprecatedReader().readUntilDelimiterAlloc(allocator, '\n', 128);
            const trimmed = std.mem.trim(u8, name_line, " \t\r\n");
            const name_copy = try allocator.dupe(u8, trimmed);
            allocator.free(name_line);
            buf_slice[i] = name_copy;
            name_slice[i] = name_copy;
        }
        provided_names = name_slice;
        name_bufs = buf_slice;
    }
    defer {
        if (name_bufs) |bufs| {
            for (bufs) |buf| allocator.free(buf);
            allocator.free(bufs);
        }
        if (provided_names) |names| allocator.free(names);
    }

    var game = try aytw.Game.init(allocator, n, .{
        .mode = mode,
        .names = if (provided_names) |names| names else null,
    });
    defer game.deinit();

    const answer_key_size: usize = if (mode == .standard) game.m else game.n;
    const answer_key = try allocator.alloc(u32, answer_key_size);
    defer allocator.free(answer_key);

    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    try game.sampleAnswerKey(answer_key, prng.random());

    var hints = hintAllocation(game.num_total_scenarios);
    if (hints > 0) {
        std.debug.print("You have {d} hint(s) available.\n", .{hints});
    }

    const total_days = calcDays(n, mode);
    const pair_count: u32 = if (mode == .standard) game.m else game.n / 2;
    var prize: u32 = 1_000_000;

    std.debug.print("\nGame started! {d} contestants, {d} days, {d} possible scenarios.\n", .{
        n,
        total_days,
        game.numRemainingScenarios(),
    });

    var won = false;
    var day: u32 = 1;
    while (day <= total_days) : (day += 1) {
        std.debug.print("\n=== Day {d}/{d} | Prize: {d} sedges ===\n", .{ day, total_days, prize });

        std.debug.print("--- Truth Booth ---\n", .{});
        while (true) {
            const action = try pauseMenu(&game, .play_truth_booth, &hints, &prize, allocator);
            switch (action) {
                .quit => return,
                .enter_truth_booth => {
                    try promptTruthBooth(&game, answer_key, allocator);
                    break;
                },
                else => {},
            }
        }

        std.debug.print("--- Matchup Ceremony ---\n", .{});
        while (true) {
            const action = try pauseMenu(&game, .play_matchup, &hints, &prize, allocator);
            switch (action) {
                .quit => return,
                .enter_matchup => {
                    const beams = try promptMatchup(&game, answer_key, allocator);
                    if (beams == 0) {
                        prize = if (prize >= 250_000) prize - 250_000 else 0;
                        std.debug.print("BLACKOUT! Prize reduced to {d} sedges.\n", .{prize});
                    }
                    if (beams == pair_count) {
                        won = true;
                    }
                    break;
                },
                else => {},
            }
        }

        if (won) break;
    }

    if (won) {
        std.debug.print("\nYou found all {d} matches! You win {d} sedges!\n", .{ pair_count, prize });
    } else {
        std.debug.print("\nGame over! You ran out of days. Better luck next time.\n", .{});
    }
}

fn calcDays(n: u32, mode: aytw.GameMode) u32 {
    const half = n / 2;
    return switch (mode) {
        .standard => half,
        .bisexual => half + (half + 3) / 4,
    };
}

const NameLabel = enum { male, female, contestant };

fn game_mode_label(mode: aytw.GameMode, i: usize, n: u32) NameLabel {
    if (mode == .bisexual) return .contestant;
    const m = n / 2;
    return if (i < m) .male else .female;
}

test "resolveName: valid integer index" {
    const names = [_][]const u8{ "Alice", "Bob", "Carol" };
    try std.testing.expectEqual(@as(?usize, 1), resolveName(&names, "1"));
}

test "resolveName: integer out of range" {
    const names = [_][]const u8{ "Alice", "Bob" };
    try std.testing.expectEqual(@as(?usize, null), resolveName(&names, "5"));
}

test "resolveName: exact name match" {
    const names = [_][]const u8{ "Alice", "Bob", "Carol" };
    try std.testing.expectEqual(@as(?usize, 2), resolveName(&names, "Carol"));
}

test "resolveName: case-insensitive match" {
    const names = [_][]const u8{ "Alice", "Bob", "Carol" };
    try std.testing.expectEqual(@as(?usize, 0), resolveName(&names, "alice"));
}

test "resolveName: whitespace trimmed" {
    const names = [_][]const u8{ "Alice", "Bob" };
    try std.testing.expectEqual(@as(?usize, 1), resolveName(&names, "  Bob  "));
}

test "resolveName: unrecognised input" {
    const names = [_][]const u8{ "Alice", "Bob" };
    try std.testing.expectEqual(@as(?usize, null), resolveName(&names, "Zara"));
}

test "hintAllocation: no hints below 500k" {
    try std.testing.expectEqual(@as(u8, 0), hintAllocation(499_999));
    try std.testing.expectEqual(@as(u8, 0), hintAllocation(0));
}

test "hintAllocation: one hint 500k to 1M" {
    try std.testing.expectEqual(@as(u8, 1), hintAllocation(500_001));
    try std.testing.expectEqual(@as(u8, 1), hintAllocation(1_000_000));
}

test "hintAllocation: two hints above 1M" {
    try std.testing.expectEqual(@as(u8, 2), hintAllocation(1_000_001));
    try std.testing.expectEqual(@as(u8, 2), hintAllocation(10_000_000));
}
