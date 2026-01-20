const std = @import("std");

pub const FACTORIALS = [_]usize{
    1,
    1,
    2,
    6,
    24,
    120,
    720,
    5040,
    40320,
    362880,
    3628800,
    39916800,
    479001600,
    6227020800,
    87178291200,
    1307674368000,
    20922789888000,
    355687428096000,
    6402373705728000,
    121645100408832000,
    2432902008176640000,
};

pub const DOUBLE_FACTORIALS = [_]usize{
    1,
    1,
    2,
    3,
    8,
    15,
    48,
    105,
    384,
    945,
    3840,
    10395,
    46080,
    135135,
    645120,
    2027025,
    10321920,
    34459425,
    185794560,
    654729075,
    3715891200,
    13749310575,
    81749606400,
    316234143225,
    1961990553600,
    7905853580625,
    51011754393600,
    213458046676875,
    1428329123020800,
    6190283353629375,
};

pub fn factorial(n: u32) usize {
    if (n > FACTORIALS.len) {
        @panic("factorial overflow");
    }

    return FACTORIALS[n];
}

pub fn doubleFactorial(n: u32) usize {
    if (n > DOUBLE_FACTORIALS.len) {
        @panic("double factorial overflow");
    }

    return DOUBLE_FACTORIALS[n];
}

/// Generates k-th permutation using Lehmer code. Time: O(N²), Space: O(N).
pub fn getPermutation(n: u32, k: usize, out: []u32) void {
    std.debug.assert(out.len == n);

    // Initialize available indices
    var available: [32]u32 = undefined;
    for (0..n) |i| {
        available[i] = @intCast(i);
    }

    // Convert k to Lehmer code and build permutation
    var k_remaining = k;
    var fact = factorial(n - 1);

    for (0..n) |pos| {
        // Get Lehmer digit for this position
        const lehmer_digit = if (fact > 0) (k_remaining / fact) else 0;

        // Take the lehmer_digit-th element from available
        out[pos] = available[lehmer_digit];

        // Remove it from available (shift remaining elements)
        for (lehmer_digit..n - pos - 1) |i| {
            available[i] = available[i + 1];
        }

        // Update k_remaining and factorial for next iteration
        if (fact > 0) {
            k_remaining %= fact;
            fact /= if (n - pos - 1 > 0) (n - pos - 1) else 1;
        }
    }
}

/// Generate the k-th perfect matching as an adjacency array. pairing[i]
/// contains the index of the element paired with i. Requires: n is even, k <
/// countPairings(n). We pass in both the `out` and the `available` slices to
/// avoid repeated allocations since this function is run millions of times.
/// available.len must equal out.len which must equal n.
pub fn getKthPairing(
    n: u32,
    k: usize,
    available: []bool,
    out: []u32,
) void {
    std.debug.assert(n % 2 == 0);
    std.debug.assert(k < doubleFactorial(n - 1));
    std.debug.assert(out.len == n);
    std.debug.assert(available.len == n);

    // Track which items are still available
    @memset(available, true);
    @memset(out, 0);

    var remaining_k = k;
    var available_count = n;

    for (0..n) |i| {
        if (!available[i]) continue;

        // Find the j-th available item (after i) to pair with i
        const pairings_per_choice = if (available_count > 2) doubleFactorial(available_count - 3) else 1;
        const partner_idx = remaining_k / pairings_per_choice; // Explain this line
        remaining_k = remaining_k % pairings_per_choice;

        // Find the actual index of the partner
        var count: usize = 0;
        var partner: usize = 0;
        for (i + 1..n) |j| {
            if (available[j]) {
                if (count == partner_idx) {
                    partner = j;
                    break;
                }
                count += 1;
            }
        }

        // Mark both as paired
        out[i] = @intCast(partner);
        out[partner] = @intCast(i);
        available[i] = false;
        available[partner] = false;
        available_count -= 2;
    }
}

pub fn countMatching(comptime T: type, left: []const T, right: []const T) usize {
    const min_len = @min(left.len, right.len);
    var count: usize = 0;

    for (0..min_len) |i| {
        if (left[i] == right[i]) {
            count += 1;
        }
    }

    return count;
}

test "countMatching" {
    const left = [_]u8{ 'a', 'b', 'c' };
    const right = [_]u8{ 'a', 'b', 'd' };
    const expected = 2;
    const actual = countMatching(u8, &left, &right);
    try std.testing.expectEqual(expected, actual);
}

test "countMatching different sizes" {
    const left = [_]u8{ 'a', 'b', 'c' };
    const right = [_]u8{ 'd', 'b', 'c', 'e' };
    const expected = 2;
    const actual = countMatching(u8, &left, &right);
    try std.testing.expectEqual(expected, actual);
}

test "getKthPairing n=2" {
    const n = 2;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    const perms = [_][]const u32{
        &[_]u32{ 1, 0 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=4" {
    const n = 4;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2 },
        &[_]u32{ 2, 3, 0, 1 },
        &[_]u32{ 3, 2, 1, 0 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=6" {
    const n = 6;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4 },
        &[_]u32{ 1, 0, 4, 5, 2, 3 },
        &[_]u32{ 1, 0, 5, 4, 3, 2 },
        &[_]u32{ 2, 3, 0, 1, 5, 4 },
        &[_]u32{ 2, 4, 0, 5, 1, 3 },
        &[_]u32{ 2, 5, 0, 4, 3, 1 },
        &[_]u32{ 3, 2, 1, 0, 5, 4 },
        &[_]u32{ 3, 4, 5, 0, 1, 2 },
        &[_]u32{ 3, 5, 4, 0, 2, 1 },
        &[_]u32{ 4, 2, 1, 5, 0, 3 },
        &[_]u32{ 4, 3, 5, 1, 0, 2 },
        &[_]u32{ 4, 5, 3, 2, 0, 1 },
        &[_]u32{ 5, 2, 1, 4, 3, 0 },
        &[_]u32{ 5, 3, 4, 1, 2, 0 },
        &[_]u32{ 5, 4, 3, 2, 1, 0 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=8" {
    const alloc = std.testing.allocator;

    const n = 8;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6 },
        &[_]u32{ 1, 0, 3, 2, 6, 7, 4, 5 },
        &[_]u32{ 1, 0, 3, 2, 7, 6, 5, 4 },
        &[_]u32{ 1, 0, 4, 5, 2, 3, 7, 6 },
        &[_]u32{ 1, 0, 4, 6, 2, 7, 3, 5 },
        &[_]u32{ 1, 0, 4, 7, 2, 6, 5, 3 },
        &[_]u32{ 1, 0, 5, 4, 3, 2, 7, 6 },
        &[_]u32{ 1, 0, 5, 6, 7, 2, 3, 4 },
        &[_]u32{ 1, 0, 5, 7, 6, 2, 4, 3 },
        &[_]u32{ 1, 0, 6, 4, 3, 7, 2, 5 },
        &[_]u32{ 1, 0, 6, 5, 7, 3, 2, 4 },
        &[_]u32{ 1, 0, 6, 7, 5, 4, 2, 3 },
        &[_]u32{ 1, 0, 7, 4, 3, 6, 5, 2 },
        &[_]u32{ 1, 0, 7, 5, 6, 3, 4, 2 },
        &[_]u32{ 1, 0, 7, 6, 5, 4, 3, 2 },
        &[_]u32{ 2, 3, 0, 1, 5, 4, 7, 6 },
        &[_]u32{ 2, 3, 0, 1, 6, 7, 4, 5 },
        &[_]u32{ 2, 3, 0, 1, 7, 6, 5, 4 },
        &[_]u32{ 2, 4, 0, 5, 1, 3, 7, 6 },
        &[_]u32{ 2, 4, 0, 6, 1, 7, 3, 5 },
        &[_]u32{ 2, 4, 0, 7, 1, 6, 5, 3 },
        &[_]u32{ 2, 5, 0, 4, 3, 1, 7, 6 },
        &[_]u32{ 2, 5, 0, 6, 7, 1, 3, 4 },
        &[_]u32{ 2, 5, 0, 7, 6, 1, 4, 3 },
        &[_]u32{ 2, 6, 0, 4, 3, 7, 1, 5 },
        &[_]u32{ 2, 6, 0, 5, 7, 3, 1, 4 },
        &[_]u32{ 2, 6, 0, 7, 5, 4, 1, 3 },
        &[_]u32{ 2, 7, 0, 4, 3, 6, 5, 1 },
        &[_]u32{ 2, 7, 0, 5, 6, 3, 4, 1 },
        &[_]u32{ 2, 7, 0, 6, 5, 4, 3, 1 },
        &[_]u32{ 3, 2, 1, 0, 5, 4, 7, 6 },
        &[_]u32{ 3, 2, 1, 0, 6, 7, 4, 5 },
        &[_]u32{ 3, 2, 1, 0, 7, 6, 5, 4 },
        &[_]u32{ 3, 4, 5, 0, 1, 2, 7, 6 },
        &[_]u32{ 3, 4, 6, 0, 1, 7, 2, 5 },
        &[_]u32{ 3, 4, 7, 0, 1, 6, 5, 2 },
        &[_]u32{ 3, 5, 4, 0, 2, 1, 7, 6 },
        &[_]u32{ 3, 5, 6, 0, 7, 1, 2, 4 },
        &[_]u32{ 3, 5, 7, 0, 6, 1, 4, 2 },
        &[_]u32{ 3, 6, 4, 0, 2, 7, 1, 5 },
        &[_]u32{ 3, 6, 5, 0, 7, 2, 1, 4 },
        &[_]u32{ 3, 6, 7, 0, 5, 4, 1, 2 },
        &[_]u32{ 3, 7, 4, 0, 2, 6, 5, 1 },
        &[_]u32{ 3, 7, 5, 0, 6, 2, 4, 1 },
        &[_]u32{ 3, 7, 6, 0, 5, 4, 2, 1 },
        &[_]u32{ 4, 2, 1, 5, 0, 3, 7, 6 },
        &[_]u32{ 4, 2, 1, 6, 0, 7, 3, 5 },
        &[_]u32{ 4, 2, 1, 7, 0, 6, 5, 3 },
        &[_]u32{ 4, 3, 5, 1, 0, 2, 7, 6 },
        &[_]u32{ 4, 3, 6, 1, 0, 7, 2, 5 },
        &[_]u32{ 4, 3, 7, 1, 0, 6, 5, 2 },
        &[_]u32{ 4, 5, 3, 2, 0, 1, 7, 6 },
        &[_]u32{ 4, 5, 6, 7, 0, 1, 2, 3 },
        &[_]u32{ 4, 5, 7, 6, 0, 1, 3, 2 },
        &[_]u32{ 4, 6, 3, 2, 0, 7, 1, 5 },
        &[_]u32{ 4, 6, 5, 7, 0, 2, 1, 3 },
        &[_]u32{ 4, 6, 7, 5, 0, 3, 1, 2 },
        &[_]u32{ 4, 7, 3, 2, 0, 6, 5, 1 },
        &[_]u32{ 4, 7, 5, 6, 0, 2, 3, 1 },
        &[_]u32{ 4, 7, 6, 5, 0, 3, 2, 1 },
        &[_]u32{ 5, 2, 1, 4, 3, 0, 7, 6 },
        &[_]u32{ 5, 2, 1, 6, 7, 0, 3, 4 },
        &[_]u32{ 5, 2, 1, 7, 6, 0, 4, 3 },
        &[_]u32{ 5, 3, 4, 1, 2, 0, 7, 6 },
        &[_]u32{ 5, 3, 6, 1, 7, 0, 2, 4 },
        &[_]u32{ 5, 3, 7, 1, 6, 0, 4, 2 },
        &[_]u32{ 5, 4, 3, 2, 1, 0, 7, 6 },
        &[_]u32{ 5, 4, 6, 7, 1, 0, 2, 3 },
        &[_]u32{ 5, 4, 7, 6, 1, 0, 3, 2 },
        &[_]u32{ 5, 6, 3, 2, 7, 0, 1, 4 },
        &[_]u32{ 5, 6, 4, 7, 2, 0, 1, 3 },
        &[_]u32{ 5, 6, 7, 4, 3, 0, 1, 2 },
        &[_]u32{ 5, 7, 3, 2, 6, 0, 4, 1 },
        &[_]u32{ 5, 7, 4, 6, 2, 0, 3, 1 },
        &[_]u32{ 5, 7, 6, 4, 3, 0, 2, 1 },
        &[_]u32{ 6, 2, 1, 4, 3, 7, 0, 5 },
        &[_]u32{ 6, 2, 1, 5, 7, 3, 0, 4 },
        &[_]u32{ 6, 2, 1, 7, 5, 4, 0, 3 },
        &[_]u32{ 6, 3, 4, 1, 2, 7, 0, 5 },
        &[_]u32{ 6, 3, 5, 1, 7, 2, 0, 4 },
        &[_]u32{ 6, 3, 7, 1, 5, 4, 0, 2 },
        &[_]u32{ 6, 4, 3, 2, 1, 7, 0, 5 },
        &[_]u32{ 6, 4, 5, 7, 1, 2, 0, 3 },
        &[_]u32{ 6, 4, 7, 5, 1, 3, 0, 2 },
        &[_]u32{ 6, 5, 3, 2, 7, 1, 0, 4 },
        &[_]u32{ 6, 5, 4, 7, 2, 1, 0, 3 },
        &[_]u32{ 6, 5, 7, 4, 3, 1, 0, 2 },
        &[_]u32{ 6, 7, 3, 2, 5, 4, 0, 1 },
        &[_]u32{ 6, 7, 4, 5, 2, 3, 0, 1 },
        &[_]u32{ 6, 7, 5, 4, 3, 2, 0, 1 },
        &[_]u32{ 7, 2, 1, 4, 3, 6, 5, 0 },
        &[_]u32{ 7, 2, 1, 5, 6, 3, 4, 0 },
        &[_]u32{ 7, 2, 1, 6, 5, 4, 3, 0 },
        &[_]u32{ 7, 3, 4, 1, 2, 6, 5, 0 },
        &[_]u32{ 7, 3, 5, 1, 6, 2, 4, 0 },
        &[_]u32{ 7, 3, 6, 1, 5, 4, 2, 0 },
        &[_]u32{ 7, 4, 3, 2, 1, 6, 5, 0 },
        &[_]u32{ 7, 4, 5, 6, 1, 2, 3, 0 },
        &[_]u32{ 7, 4, 6, 5, 1, 3, 2, 0 },
        &[_]u32{ 7, 5, 3, 2, 6, 1, 4, 0 },
        &[_]u32{ 7, 5, 4, 6, 2, 1, 3, 0 },
        &[_]u32{ 7, 5, 6, 4, 3, 1, 2, 0 },
        &[_]u32{ 7, 6, 3, 2, 5, 4, 1, 0 },
        &[_]u32{ 7, 6, 4, 5, 2, 3, 1, 0 },
        &[_]u32{ 7, 6, 5, 4, 3, 2, 1, 0 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=10" {
    const n = 10;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    // Not feasible to test all 945 possibilities so just pick first 10.
    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 9, 6, 7 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 9, 8, 7, 6 },
        &[_]u32{ 1, 0, 3, 2, 6, 7, 4, 5, 9, 8 },
        &[_]u32{ 1, 0, 3, 2, 6, 8, 4, 9, 5, 7 },
        &[_]u32{ 1, 0, 3, 2, 6, 9, 4, 8, 7, 5 },
        &[_]u32{ 1, 0, 3, 2, 7, 6, 5, 4, 9, 8 },
        &[_]u32{ 1, 0, 3, 2, 7, 8, 9, 4, 5, 6 },
        &[_]u32{ 1, 0, 3, 2, 7, 9, 8, 4, 6, 5 },
        &[_]u32{ 1, 0, 3, 2, 8, 6, 5, 9, 4, 7 },
        &[_]u32{ 1, 0, 3, 2, 8, 7, 9, 5, 4, 6 },
        &[_]u32{ 1, 0, 3, 2, 8, 9, 7, 6, 4, 5 },
        &[_]u32{ 1, 0, 3, 2, 9, 6, 5, 8, 7, 4 },
        &[_]u32{ 1, 0, 3, 2, 9, 7, 8, 5, 6, 4 },
        &[_]u32{ 1, 0, 3, 2, 9, 8, 7, 6, 5, 4 },
        &[_]u32{ 1, 0, 4, 5, 2, 3, 7, 6, 9, 8 },
        &[_]u32{ 1, 0, 4, 5, 2, 3, 8, 9, 6, 7 },
        &[_]u32{ 1, 0, 4, 5, 2, 3, 9, 8, 7, 6 },
        &[_]u32{ 1, 0, 4, 6, 2, 7, 3, 5, 9, 8 },
        &[_]u32{ 1, 0, 4, 6, 2, 8, 3, 9, 5, 7 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=12" {
    const n = 12;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    // Not feasible to test all possibilities so just pick first 10.
    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 11, 8, 9 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 11, 10, 9, 8 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 9, 6, 7, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 10, 6, 11, 7, 9 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 11, 6, 10, 9, 7 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 9, 8, 7, 6, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 9, 10, 11, 6, 7, 8 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 9, 11, 10, 6, 8, 7 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 10, 8, 7, 11, 6, 9 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 10, 9, 11, 7, 6, 8 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 10, 11, 9, 8, 6, 7 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 11, 8, 7, 10, 9, 6 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 11, 9, 10, 7, 8, 6 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 11, 10, 9, 8, 7, 6 },
        &[_]u32{ 1, 0, 3, 2, 6, 7, 4, 5, 9, 8, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 6, 7, 4, 5, 10, 11, 8, 9 },
        &[_]u32{ 1, 0, 3, 2, 6, 7, 4, 5, 11, 10, 9, 8 },
        &[_]u32{ 1, 0, 3, 2, 6, 8, 4, 9, 5, 7, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 6, 8, 4, 10, 5, 11, 7, 9 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=14" {
    const n = 14;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    // Not feasible to test all possibilities so just pick first 10.
    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 13, 10, 11 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 13, 12, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 11, 8, 9, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 12, 8, 13, 9, 11 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 13, 8, 12, 11, 9 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 11, 10, 9, 8, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 11, 12, 13, 8, 9, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 11, 13, 12, 8, 10, 9 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 12, 10, 9, 13, 8, 11 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 12, 11, 13, 9, 8, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 12, 13, 11, 10, 8, 9 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 13, 10, 9, 12, 11, 8 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 13, 11, 12, 9, 10, 8 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 13, 12, 11, 10, 9, 8 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 9, 6, 7, 11, 10, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 9, 6, 7, 12, 13, 10, 11 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 9, 6, 7, 13, 12, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 10, 6, 11, 7, 9, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 8, 10, 6, 12, 7, 13, 9, 11 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=16" {
    const n = 16;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    // Not feasible to test all possibilities so just pick first 10.
    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 15, 12, 13 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 15, 14, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 13, 10, 11, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 14, 10, 15, 11, 13 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 15, 10, 14, 13, 11 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 13, 12, 11, 10, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 13, 14, 15, 10, 11, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 13, 15, 14, 10, 12, 11 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 14, 12, 11, 15, 10, 13 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 14, 13, 15, 11, 10, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 14, 15, 13, 12, 10, 11 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 15, 12, 11, 14, 13, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 15, 13, 14, 11, 12, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 15, 14, 13, 12, 11, 10 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 11, 8, 9, 13, 12, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 11, 8, 9, 14, 15, 12, 13 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 11, 8, 9, 15, 14, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 12, 8, 13, 9, 11, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 10, 12, 8, 14, 9, 15, 11, 13 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=18" {
    const n = 18;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    // Not feasible to test all possibilities so just pick first 10.
    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14, 17, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 16, 17, 14, 15 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 17, 16, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 15, 12, 13, 17, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 16, 12, 17, 13, 15 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 17, 12, 16, 15, 13 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 15, 14, 13, 12, 17, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 15, 16, 17, 12, 13, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 15, 17, 16, 12, 14, 13 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 16, 14, 13, 17, 12, 15 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 16, 15, 17, 13, 12, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 16, 17, 15, 14, 12, 13 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 17, 14, 13, 16, 15, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 17, 15, 16, 13, 14, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 17, 16, 15, 14, 13, 12 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 13, 10, 11, 15, 14, 17, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 13, 10, 11, 16, 17, 14, 15 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 13, 10, 11, 17, 16, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 14, 10, 15, 11, 13, 17, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 12, 14, 10, 16, 11, 17, 13, 15 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}

test "getKthPairing n=20" {
    const n = 20;

    const alloc = std.testing.allocator;
    const available = try alloc.alloc(bool, n);
    defer alloc.free(available);
    const out = try alloc.alloc(u32, n);
    defer alloc.free(out);

    // Not feasible to test all possibilities so just pick first 10.
    const perms = [_][]const u32{
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14, 17, 16, 19, 18 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14, 18, 19, 16, 17 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14, 19, 18, 17, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 16, 17, 14, 15, 19, 18 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 16, 18, 14, 19, 15, 17 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 16, 19, 14, 18, 17, 15 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 17, 16, 15, 14, 19, 18 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 17, 18, 19, 14, 15, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 17, 19, 18, 14, 16, 15 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 18, 16, 15, 19, 14, 17 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 18, 17, 19, 15, 14, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 18, 19, 17, 16, 14, 15 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 19, 16, 15, 18, 17, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 19, 17, 18, 15, 16, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 19, 18, 17, 16, 15, 14 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 15, 12, 13, 17, 16, 19, 18 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 15, 12, 13, 18, 19, 16, 17 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 15, 12, 13, 19, 18, 17, 16 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 16, 12, 17, 13, 15, 19, 18 },
        &[_]u32{ 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 14, 16, 12, 18, 13, 19, 15, 17 },
    };

    for (0..perms.len) |i| {
        getKthPairing(n, i, available, out);
        try std.testing.expectEqualSlices(u32, perms[i], out);
    }
}
