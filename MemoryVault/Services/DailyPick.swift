import Foundation

/// Chooses which memory to resurface. Stable for a given day so the front page
/// shows the same "memory of the day" until you shuffle.
enum DailyPick {
    static func onThisDay(_ memory: Memory, on date: Date) -> Bool {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let md = memory.memoryDate
        return md.effectivePrecision == .day && md.month == c.month && md.day == c.day && md.year != c.year
    }

    static func memoryOfTheDay(from memories: [Memory], on date: Date = Date()) -> Memory? {
        guard !memories.isEmpty else { return nil }
        let seed = daySeed(date)
        let anniversaries = memories.filter { onThisDay($0, on: date) }
        let pool = anniversaries.isEmpty ? memories : anniversaries
        let sorted = pool.sorted { $0.createdAt < $1.createdAt }
        return sorted[Int(mix(seed) % UInt64(sorted.count))]
    }

    static func reminderPick(for date: Date, from memories: [Memory], excluding used: Set<UUID>) -> Memory? {
        let anniversaries = memories.filter { onThisDay($0, on: date) && !used.contains($0.id) }
        if let pick = anniversaries.randomElement() { return pick }
        // Favor favorites and older entries a little, but keep it random.
        let available = memories.filter { !used.contains($0.id) }
        let pool = available.isEmpty ? memories : available
        let favorites = pool.filter(\.isFavorite)
        if !favorites.isEmpty, Int.random(in: 0..<4) == 0 { return favorites.randomElement() }
        return pool.randomElement()
    }

    private static func daySeed(_ date: Date) -> UInt64 {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return UInt64((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0))
    }

    /// SplitMix64 finalizer: turns a small seed into a well-spread number.
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
