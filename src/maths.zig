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

pub fn factorial(n: u32) usize {
    if (n > 20) {
        @panic("factorial overflow");
    }

    return FACTORIALS[n];
}

/// Generates k-th permutation using Lehmer code. Time: O(N²), Space: O(N).
pub fn getPermutation(n: u32, k: usize, out: []u32) !void {
    if (k >= factorial(n)) {
        return error.IndexOutOfBounds;
    }

    // Initialise with monotonically increasing list [0, 1, ..., n-1]
    for (0..n) |i| {
        out[i] = @intCast(i);
    }

    var k_remain = k;
    var fact = factorial(n - 1);

    for (0..n - 1) |i| {
        const idx = k_remain / fact;
        const perm_idx = i + idx;

        // Rotate elements from i to perm_idx
        const temp = out[perm_idx];
        for (i..perm_idx) |j| {
            out[j] = out[j + 1];
        }
        out[i] = temp;

        k_remain %= fact;
        //if (fact > 1) {
        if (n - i - 1 > 1) {
            fact /= (n - i - 1);
        }
    }
}

pub fn permute(comptime T: type, list: []T) !PermutationIterator {
    if (list.len > 16) {
        return error.TooManyElements;
    }

    return PermutationIterator(u32){
        .list = list[0..],
        .size = @intCast(list.len),
        .counters = [_]u4{0} ** 16,
        .level = 0,
        .first = true,
    };
}

inline fn swap(comptime T: type, a: *T, b: *T) void {
    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

// Inspired by https://github.com/svc-user/zig-permutate/blob/master/src/permutate.zig.
// Uses Heap's algorithm.
pub fn PermutationIterator(comptime T: type) type {
    return struct {
        list: []T,
        size: u4,
        counters: [16]u4,
        level: u4,
        first: bool,

        pub fn next(self: *@This()) ?[]T {
            if (self.first) {
                // First iteration always just returns the original list unmodified.
                self.first = false;
                return self.list;
            }

            while (self.level < self.size) {
                if (self.counters[self.level] < self.level) {
                    if (self.level % 2 == 0) {
                        swap(T, &self.list[0], &self.list[self.level]);
                    } else {
                        swap(T, &self.list[self.counters[self.level]], &self.list[self.level]);
                    }

                    self.counters[self.level] += 1;
                    self.level = 0;

                    return self.list;
                } else {
                    self.counters[self.level] = 0;
                    self.level += 1;
                }
            }

            return null;
        }
    };
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
