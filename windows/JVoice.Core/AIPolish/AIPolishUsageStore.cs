using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace JVoice.Core.AIPolish;

/// <summary>
/// What AI Polish has cost and the prepaid BALANCE it draws from (port of the Mac's
/// <c>AIPolishUsageStore</c>), persisted to one small JSON file (<c>%APPDATA%\JVoice\ai-polish-usage.json</c>
/// in the app) — numbers only, never text or the key. Every billed reply is priced from the token
/// counts Anthropic returned (exact, not estimated) and added to "this month" (restarts on the first
/// polish of a new calendar month, local time) and "all time", and subtracted from the balance.
///
/// The balance is JVoice's own spending limit: it starts at $0 (so nothing is sent until the user tops
/// it up in Settings), every billed reply comes off it, and at $0 the coordinator stops sending
/// dictations. It is a local counter, not money held anywhere — Anthropic bills the user's own account.
/// There is no Reset for the spent totals (David removed it on the Mac). Thread-safe: a reply that
/// arrives after the deadline is recorded from a pool thread.
/// </summary>
public sealed class AIPolishUsageStore
{
    public sealed record Totals(double MonthCost = 0, int MonthPolishes = 0, double TotalCost = 0, int TotalPolishes = 0);

    /// <summary>The one HUD pill shown when a reply uses up the balance (the dictation itself still pastes).</summary>
    public const string BalanceUsedUpMessage = "AI Polish balance used up — add more in Settings";

    /// <summary>The largest single top-up Settings accepts (USD) — guards a typo like 5000 for 5.</summary>
    public const double MaxTopUp = 1000;

    /// <summary>True when a dictation may go to Claude: the toggle is on, a key is saved and money is left.</summary>
    public static bool ShouldPolish(bool enabled, bool hasKey, double balance) => enabled && hasKey && balance > 0;

    private sealed class Dto
    {
        [JsonPropertyName("month")] public string? Month { get; set; }
        [JsonPropertyName("monthCost")] public double MonthCost { get; set; }
        [JsonPropertyName("monthPolishes")] public int MonthPolishes { get; set; }
        [JsonPropertyName("totalCost")] public double TotalCost { get; set; }
        [JsonPropertyName("totalPolishes")] public int TotalPolishes { get; set; }
        [JsonPropertyName("balance")] public double Balance { get; set; }
        [JsonPropertyName("lastTopUp")] public double LastTopUp { get; set; }
    }

    private readonly string? _path;
    private readonly object _gate = new();
    private Dto _data;

    /// <param name="path">The JSON file; null keeps everything in memory (renders/previews).</param>
    public AIPolishUsageStore(string? path)
    {
        _path = path;
        _data = Load();
    }

    /// <summary>"2026-10" — the calendar month <paramref name="date"/> falls in, in local time.</summary>
    public static string MonthKey(DateTime date) =>
        (date.Kind == DateTimeKind.Utc ? date.ToLocalTime() : date).ToString("yyyy-MM", CultureInfo.InvariantCulture);

    /// <summary>USD left to spend on AI Polish (never negative; $0 until the first top-up).</summary>
    public double Balance { get { lock (_gate) return Math.Max(0, Finite(_data.Balance)); } }

    /// <summary>The most recent top-up amount — the Settings bar shows <c>Balance / LastTopUp</c>.</summary>
    public double LastTopUp { get { lock (_gate) return Math.Max(0, Finite(_data.LastTopUp)); } }

    /// <summary>Remaining share of the last top-up, 0…1 (0 when there never was one; a balance above the
    /// last top-up — money left over from before it — reads as full).</summary>
    public double RemainingFraction
    {
        get
        {
            double topUp = LastTopUp;
            return topUp > 0 ? Math.Min(1, Math.Max(0, Balance / topUp)) : 0;
        }
    }

    /// <summary>Adds <paramref name="amount"/> USD and remembers it as the last top-up. Non-positive,
    /// non-finite or over-<see cref="MaxTopUp"/> amounts are refused (false).</summary>
    public bool AddBalance(double amount)
    {
        if (!double.IsFinite(amount) || amount <= 0 || amount > MaxTopUp) return false;
        lock (_gate)
        {
            _data.Balance = Math.Max(0, Finite(_data.Balance)) + amount;
            _data.LastTopUp = amount;
            Save();
        }
        return true;
    }

    /// <summary>Takes <paramref name="amount"/> USD off the balance (an accidental top-up: $10 added,
    /// $5 meant), never below $0. Spent totals and the last top-up are untouched. Non-positive or
    /// non-finite amounts are refused (false).</summary>
    public bool RemoveBalance(double amount)
    {
        if (!double.IsFinite(amount) || amount <= 0) return false;
        lock (_gate)
        {
            _data.Balance = Math.Max(0, Math.Max(0, Finite(_data.Balance)) - amount);
            Save();
        }
        return true;
    }

    public Totals GetTotals(DateTime? now = null)
    {
        lock (_gate)
        {
            bool sameMonth = _data.Month == MonthKey(now ?? DateTime.Now);
            return new Totals(
                sameMonth ? _data.MonthCost : 0,
                sameMonth ? _data.MonthPolishes : 0,
                _data.TotalCost,
                _data.TotalPolishes);
        }
    }

    /// <summary>Adds one billed reply and subtracts its cost from the balance (clamped at $0). A reply
    /// that came back but was not used (a fallback) still cost tokens, so it counts too; a call that
    /// never got a reply has no usage and isn't recorded. Returns true when THIS reply used the balance
    /// up (it was above $0 and is now $0) — the coordinator shows its one "used up" pill on that, never
    /// again while the balance stays at $0.</summary>
    public bool Record(AIPolishUsage usage, string model, DateTime? now = null)
    {
        if (AIPolishRequest.Cost(usage, model) is not { } cost) return false;
        lock (_gate)
        {
            var at = now ?? DateTime.Now;
            double before = Math.Max(0, Finite(_data.Balance));
            double after = Math.Max(0, before - cost);
            var current = GetTotals(at);
            _data.Balance = after;
            _data.Month = MonthKey(at);
            _data.MonthCost = current.MonthCost + cost;
            _data.MonthPolishes = current.MonthPolishes + 1;
            _data.TotalCost = current.TotalCost + cost;
            _data.TotalPolishes = current.TotalPolishes + 1;
            Save();
            return before > 0 && after <= 0;
        }
    }

    /// <summary>"$0.42", or four decimals under a cent so a few polishes don't read as "$0.00".</summary>
    public static string Dollars(double amount) =>
        amount > 0 && amount < 0.01
            ? "$" + amount.ToString("0.0000", CultureInfo.InvariantCulture)
            : "$" + amount.ToString("0.00", CultureInfo.InvariantCulture);

    private static double Finite(double value) => double.IsFinite(value) ? value : 0;

    private Dto Load()
    {
        if (_path is null) return new Dto();
        try
        {
            if (!File.Exists(_path)) return new Dto();
            return JsonSerializer.Deserialize<Dto>(File.ReadAllText(_path)) ?? new Dto();
        }
        catch
        {
            return new Dto(); // a corrupt file reads as $0: AI Polish simply stays off until a top-up
        }
    }

    private void Save()
    {
        if (_path is null) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            string tmp = _path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(_data, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(tmp, _path, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Non-fatal: the in-memory numbers still gate this session.
        }
    }
}
