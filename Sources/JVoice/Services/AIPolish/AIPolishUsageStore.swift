import Foundation

/// What AI Polish has cost, from the token counts Anthropic returns with each reply (exact, not
/// estimated) priced by `AIPolishRequest.cost`. Persisted in UserDefaults like `StatsStore` — totals
/// only, never text or the key. "This month" restarts on the first polish of a new calendar month.
final class AIPolishUsageStore {
    struct Totals: Equatable, Sendable {
        var monthCost: Double = 0
        var monthPolishes = 0
        var totalCost: Double = 0
        var totalPolishes = 0
    }

    /// The Settings bar fills toward this (USD per month). Only a display reference — JVoice never
    /// stops polishing because of it; the real cap is the spend limit set in the Anthropic console.
    static let defaultMonthlyBudget: Double = 10

    private let defaults: UserDefaults

    private enum Key {
        static let month = "jvoice.app.aiPolish.usage.month"
        static let monthCost = "jvoice.app.aiPolish.usage.monthCost"
        static let monthPolishes = "jvoice.app.aiPolish.usage.monthPolishes"
        static let totalCost = "jvoice.app.aiPolish.usage.totalCost"
        static let totalPolishes = "jvoice.app.aiPolish.usage.totalPolishes"
        static let monthlyBudget = "jvoice.app.aiPolish.monthlyBudget"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// "2026-10" — the calendar month `date` falls in, in the user's time zone.
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    var monthlyBudget: Double {
        get { (defaults.object(forKey: Key.monthlyBudget) as? Double) ?? Self.defaultMonthlyBudget }
        set { defaults.set(max(0, newValue), forKey: Key.monthlyBudget) }
    }

    func totals(now: Date = Date()) -> Totals {
        let sameMonth = defaults.string(forKey: Key.month) == Self.monthKey(now)
        return Totals(monthCost: sameMonth ? defaults.double(forKey: Key.monthCost) : 0,
                      monthPolishes: sameMonth ? defaults.integer(forKey: Key.monthPolishes) : 0,
                      totalCost: defaults.double(forKey: Key.totalCost),
                      totalPolishes: defaults.integer(forKey: Key.totalPolishes))
    }

    /// Adds one billed reply. A reply that came back but was not used (a fallback) still cost
    /// tokens, so it counts too; a call that never got a reply (no key, offline, timeout) has no
    /// usage and isn't recorded.
    func record(_ usage: AIPolishRequest.Usage, model: String, now: Date = Date()) {
        guard let cost = AIPolishRequest.cost(usage, model: model) else { return }
        var current = totals(now: now)
        current.monthCost += cost
        current.monthPolishes += 1
        current.totalCost += cost
        current.totalPolishes += 1
        defaults.set(Self.monthKey(now), forKey: Key.month)
        defaults.set(current.monthCost, forKey: Key.monthCost)
        defaults.set(current.monthPolishes, forKey: Key.monthPolishes)
        defaults.set(current.totalCost, forKey: Key.totalCost)
        defaults.set(current.totalPolishes, forKey: Key.totalPolishes)
    }

    /// Clears the totals (the budget stays).
    func reset() {
        for key in [Key.month, Key.monthCost, Key.monthPolishes, Key.totalCost, Key.totalPolishes] {
            defaults.removeObject(forKey: key)
        }
    }

    /// "$0.42", or four decimals under a cent so a few polishes don't read as "$0.00".
    static func dollars(_ amount: Double) -> String {
        if amount > 0, amount < 0.01 { return String(format: "$%.4f", amount) }
        return String(format: "$%.2f", amount)
    }
}
