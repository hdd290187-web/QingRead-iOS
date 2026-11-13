import Foundation

/// A window is always a contiguous part of the book. Completed preloads may be
/// sparse, but a missing chapter must never disappear from the reading order.
enum ScrollWindow {
    static func chapters(available: Set<Int>, mounted: [Int], anchor: Int,
                         visible: Set<Int>, deferRebase: Bool) -> [Int] {
        guard available.contains(anchor) else { return mounted }
        if deferRebase, let last = mounted.last {
            var result = mounted, next = last + 1
            while available.contains(next) { result.append(next); next += 1 }
            return result
        }
        var first = anchor, last = anchor
        let lower = min(anchor - 2, visible.min() ?? anchor)
        let upper = max(anchor + 2, visible.max() ?? anchor)
        while first > lower, available.contains(first - 1) { first -= 1 }
        while last < upper, available.contains(last + 1) { last += 1 }
        return Array(first...last)
    }
}
