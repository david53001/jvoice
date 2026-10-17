import Foundation

/// What AI Polish has cost, from the token counts Anthropic returns with each reply (exact, not
/// estimated) priced by `AIPolishRequest.cost`, and the prepaid BALANCE it draws from. Persisted in
/// UserDefaults like `StatsStore` — totals only, never text or the key. "This month" restarts on the
/// first polish of a new calendar month.
///
/// The balance is JVoice's own spending limit: the user tops it up in Settings (it starts at $0, so
/// AI Polish stays off until they do), every billed reply is subtracted from it, and at $0 the
/// coordinator stops sending dictations (`shouldPolish`). It is a local counter, not money held
/// anywhere — Anthropic bills the user's own account as before.
final class AIPolishUsageStore {
    struct Totals: Equatable, Sendable {
        var monthCost: Double = 0
        var monthPolishes = 0
        var totalCost: Double = 0
        var totalPolishes = 0
    }

    /// The one HUD pill shown when a reply uses up the balance (the dictation itself still pastes).
    static let balanceUsedUpMessage = "AI Polish balance used up — add more in Settings"

    /// The largest single top-up Settings accepts (USD) — guards a typo like 5000 for 5.
    static let maxTopUp: Double = 1000

    /// True when a dictation may go to Claude: the toggle is on, a key is saved and money is left.
    static func shouldPolish(enabled: Bool, hasKey: Bool, balance: Double) -> Bool {
        enabled && hasKey && balance > 0
    }

    private let defaults: UserDefaults

    private enum Key {
        static let month = "jvoice.app.aiPolish.usage.month"
        static let monthCost = "jvoice.app.aiPolish.usage.monthCost"
        static let monthPolishes = "jvoice.app.aiPolish.usage.monthPolishes"
        static let totalCost = "jvoice.app.aiPolish.usage.totalCost"
        static let totalPolishes = "jvoice.app.aiPolish.usage.totalPolishes"
        static let balance = "jvoice.app.aiPolish.balance"
        static let lastTopUp = "jvoice.app.aiPolish.lastTopUp"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// "2026-10" — the calendar month `date` falls in, in the user's time zone.
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// USD left to spend on AI Polish (never negative; $0 until the first top-up).
    var balance: Double {
        max(0, defaults.double(forKey: Key.balance))
    }

    /// The most recent top-up amount — the Settings bar shows `balance / lastTopUp`.
    var lastTopUp: Double {
        defaults.double(forKey: Key.lastTopUp)
    }

    /// Remaining share of the last top-up, 0…1 (0 when there never was one; a balance above the last
    /// top-up — money left over from before it — reads as full).
    var remainingFraction: Double {
        let topUp = lastTopUp
        guard topUp > 0 else { return 0 }
        return min(1, max(0, balance / topUp))
    }

    /// Adds `amount` USD to the balance and remembers it as the last top-up. Non-positive, non-finite
    /// or over-`maxTopUp` amounts are refused (returns false).
    @discardableResult
    func addBalance(_ amount: Double) -> Bool {
        guard amount.isFinite, amount > 0, amount <= Self.maxTopUp else { return false }
        let newBalance = balance + amount
        defaults.set(newBalance, forKey: Key.balance)
        defaults.set(amount, forKey: Key.lastTopUp)
        return true
    }

    func totals(now: Date = Date()) -> Totals {
        let sameMonth = defaults.string(forKey: Key.month) == Self.monthKey(now)
        return Totals(monthCost: sameMonth ? defaults.double(forKey: Key.monthCost) : 0,
                      monthPolishes: sameMonth ? defaults.integer(forKey: Key.monthPolishes) : 0,
                      totalCost: defaults.double(forKey: Key.totalCost),
                      totalPolishes: defaults.integer(forKey: Key.totalPolishes))
    }

    /// Adds one billed reply and subtracts its cost from the balance (clamped at $0). A reply that
    /// came back but was not used (a fallback) still cost tokens, so it counts too; a call that
    /// never got a reply (no key, offline, timeout) has no usage and isn't recorded. Returns true
    /// when THIS reply used the balance up (it was above $0 and is now $0) — the coordinator shows
    /// its one "used up" pill on that, never again while the balance stays at $0.
    @discardableResult
    func record(_ usage: AIPolishRequest.Usage, model: String, now: Date = Date()) -> Bool {
        guard let cost = AIPolishRequest.cost(usage, model: model) else { return false }
        let before = balance
        let after = max(0, before - cost)
        defaults.set(after, forKey: Key.balance)
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
        return before > 0 && after <= 0
    }

    /// Clears the spent totals. The balance (and the last top-up) stays — it is money, not a stat.
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
