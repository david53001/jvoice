using System.Windows.Threading;
using JVoice.App.AIPolish;
using JVoice.App.Platform;
using JVoice.Core;
using JVoice.Core.AIPolish;
using JVoice.Core.Models;
using JVoice.Core.Text;

namespace JVoice.App;

/// <summary>
/// AI Polish (opt-in, bring your own Anthropic key) — the coordinator's half: the Settings state, the
/// key and balance actions, and <see cref="PolishAsync"/>, the step FinishTranscriptionAsync runs after
/// the local cleanup + maths and before paste. Port of the Mac's VoiceCoordinator AI Polish code
/// (branch feat/ai-polish); the pure logic lives in JVoice.Core/AIPolish. Rules: off by default;
/// ANY failure pastes the local text; only the reason is logged, never the text or the key.
/// </summary>
public sealed partial class VoiceCoordinator
{
    private bool _aiPolish;
    private readonly ApiKeyStore _apiKeys = DpapiKeyProtector.CreateStore();
    private readonly AIPolishUsageStore _polishUsage = new(PlatformPaths.AiPolishUsageFile);
    /// The "previous sentences": the last few PASTED results, IN MEMORY ONLY (UI thread).
    private readonly AIPolishContext _polishContext = new();
    /// A reply emptied the balance: show the ONE "used up" pill after the next successful paste. Kept
    /// pending (not dropped) when that dictation's paste fails — Mac review item.
    private volatile bool _polishUsedUpPending;
    /// Renders only (--settings-render aipolish-*): the card shows a staged state; nothing reads or
    /// writes the real key or balance.
    private bool _aiPolishPreview;

    // ---- bindable state (Settings → AI Polish) ----

    private string? _apiKeyHint;
    private double _polishBalance;
    private double _polishLastTopUp;
    private AIPolishUsageStore.Totals _polishTotals = new();

    /// The stored choice. The switch shows <see cref="AiPolishSwitch"/> instead.
    public bool AiPolish
    {
        get => _aiPolish;
        set
        {
            if (_aiPolish == value) return;
            _aiPolish = value;
            if (!value) _polishContext.Clear(); // turning it off also forgets the in-memory context
            PersistSettings();
            RaiseAiPolishFlags();
        }
    }

    /// The switch: reads ON only while polishing can actually happen (key + money left). At $0 it reads
    /// off and can't be turned on; the stored choice comes back by itself once money is added.
    public bool AiPolishSwitch
    {
        get => _aiPolish && HasApiKey && _polishBalance > 0;
        set { if (value != AiPolishSwitch) AiPolish = value; }
    }

    public bool CanToggleAiPolish => HasApiKey && _polishBalance > 0;
    public bool HasApiKey => _apiKeyHint is not null;
    /// "Key saved" / "No key saved" — the hint itself sits in the empty key field (WINDOWS-HANDOFF §2.1).
    public string ApiKeyStatusText => _apiKeyHint is not null ? "Key saved" : "No key saved";

    /// The empty key field's placeholder: the saved key's hint ("••••abcd" — dots + last 4, never the
    /// key), or the key format when none is saved.
    public string ApiKeyPlaceholder => _apiKeyHint ?? "sk-ant-\u2026";

    /// The caption under the switch, or null when it can be used.
    public string? AiPolishCaption =>
        !HasApiKey ? "Save your Anthropic API key below to turn this on."
        : _polishBalance <= 0 ? "Add a balance to turn this on."
        : null;
    public bool HasAiPolishCaption => AiPolishCaption is not null;

    public double PolishBalance => _polishBalance;
    public string PolishBalanceText => $"Balance: {AIPolishUsageStore.Dollars(_polishBalance)} left";
    /// Balance ÷ last top-up, 0…1, for the bar.
    public double PolishFraction => _polishLastTopUp > 0 ? Math.Min(1, Math.Max(0, _polishBalance / _polishLastTopUp)) : 0;
    public bool PolishUsedUp => _polishBalance <= 0 && _polishLastTopUp > 0;
    public bool CanRemoveBalance => _polishBalance > 0;
    public string PolishMonthText => $"This month: {AIPolishUsageStore.Dollars(_polishTotals.MonthCost)} · {Polishes(_polishTotals.MonthPolishes)}";
    public string PolishAllTimeText => $"All time: {AIPolishUsageStore.Dollars(_polishTotals.TotalCost)} · {Polishes(_polishTotals.TotalPolishes)}";

    private static string Polishes(int n) => n == 1 ? "1 polish" : $"{n} polishes";

    private void RaiseAiPolishFlags()
    {
        foreach (var name in new[]
                 {
                     nameof(AiPolish), nameof(AiPolishSwitch), nameof(CanToggleAiPolish), nameof(HasApiKey),
                     nameof(ApiKeyStatusText), nameof(ApiKeyPlaceholder), nameof(AiPolishCaption), nameof(HasAiPolishCaption), nameof(PolishBalance),
                     nameof(PolishBalanceText), nameof(PolishFraction), nameof(PolishUsedUp), nameof(CanRemoveBalance),
                     nameof(PolishMonthText), nameof(PolishAllTimeText),
                 })
            Raise(name);
    }

    // ---- key + balance actions (Settings) ----

    /// Re-reads the key hint, balance and totals — Settings calls it when shown. A key removed outside
    /// JVoice can't leave the switch on.
    public void RefreshAiPolishStatus()
    {
        if (_aiPolishPreview) return;
        _apiKeyHint = _apiKeys.SavedHint();
        if (_apiKeyHint is null && _aiPolish) { _aiPolish = false; _polishContext.Clear(); PersistSettings(); }
        RefreshPolishUsage();
    }

    private void RefreshPolishUsage()
    {
        if (_aiPolishPreview) return;
        _polishBalance = _polishUsage.Balance;
        _polishLastTopUp = _polishUsage.LastTopUp;
        _polishTotals = _polishUsage.GetTotals();
        RaiseAiPolishFlags();
    }

    /// Saves <paramref name="key"/> (replacing any saved one). False when it couldn't be written.
    public bool SaveApiKey(string key)
    {
        if (_aiPolishPreview) return false;
        bool saved = _apiKeys.Save(key);
        RefreshAiPolishStatus();
        return saved;
    }

    /// Removes the key and turns AI Polish off (it can't run without one).
    public void RemoveApiKey()
    {
        if (_aiPolishPreview) return;
        _apiKeys.Delete();
        AiPolish = false;
        RefreshAiPolishStatus();
    }

    /// The saved key itself — only for the Settings eye button.
    public string? RevealApiKey() => _aiPolishPreview ? null : _apiKeys.Read();

    /// Tests <paramref name="candidate"/> (what's typed) or, when it's empty, the saved key.
    public async Task<string> TestApiKeyAsync(string candidate)
    {
        string typed = candidate.Trim();
        string? key = typed.Length > 0 ? typed : await Task.Run(_apiKeys.Read);
        if (string.IsNullOrEmpty(key)) return "No key to test — paste one first.";
        return (await AIPolishKeyCheck.CheckAsync(key, HttpPolishTransport.Shared)).Message;
    }

    /// Settings → Add. False when the amount was refused (≤ 0, not a number, or over the cap).
    public bool AddPolishBalance(double amount)
    {
        if (_aiPolishPreview) return false;
        bool added = _polishUsage.AddBalance(amount);
        RefreshPolishUsage();
        return added;
    }

    /// Settings → Remove: takes an amount back off the balance (never below $0).
    public bool RemovePolishBalance(double amount)
    {
        if (_aiPolishPreview) return false;
        bool removed = _polishUsage.RemoveBalance(amount);
        RefreshPolishUsage();
        return removed;
    }

    /// Every reply Anthropic billed counts, used or not, and comes off the balance — including one that
    /// arrived after the deadline (called from a pool thread then). Returns true when it emptied it.
    private bool RecordPolishUsage(AIPolishUsage usage)
    {
        bool ranOut = _polishUsage.Record(usage, AIPolishOptions.Standard.Model);
        if (ranOut) _polishUsedUpPending = true;
        _ = _dispatcher.InvokeAsync(RefreshPolishUsage);
        return ranOut;
    }

    // ---- the dictation step ----

    /// The text to paste: <paramref name="processed"/> polished by Claude, or unchanged on ANY failure,
    /// when AI Polish is off, at $0, or for a dictation under 3 words. Shows "AI refining" meanwhile.
    /// Called from FinishTranscriptionAsync, which runs on the UI thread between awaits; the key read
    /// and the HTTP call run on the pool (AIPolishClient). Never throws.
    private async Task<string> PolishAsync(string processed, string? targetApp, ToneStyle tone,
        IReadOnlyList<string> vocabulary, CancellationToken ct)
    {
        try
        {
            // The key's presence isn't checked here (a file read + DPAPI on every dictation): a missing
            // key is the client's own fallback(no-key), and the switch can't be turned on without one.
            switch (AIPolishGate.Plan(_aiPolish, _polishUsage.Balance, processed))
            {
                case PolishStep.Off:
                    return processed;
                case PolishStep.SkipBalance:
                    DiagnosticLog.Write("AIPolish skipped(balance)");
                    return processed;
                case PolishStep.SkipShort:
                    DiagnosticLog.Write("AIPolish skipped(short)");
                    return processed;
            }

            await _dispatcher.InvokeAsync(() => UpdateHud(HudState.Refining));
            var previous = await _dispatcher.InvokeAsync(() => _polishContext.Previous(targetApp));
            var polish = await new AIPolishClient(HttpPolishTransport.Shared, AIPolishGate.Timeout)
                .PolishAsync(processed, previous, tone, vocabulary, _apiKeys.Read, ct: ct,
                    onLateUsage: usage => RecordPolishUsage(usage));
            if (polish.Usage is { } billed) RecordPolishUsage(billed);

            string finalText = processed;
            // The tone the user chose wins: its formatting (Casual's missing final period, Formal's
            // capital + period) is applied to the reply as it was to the local text. A punctuation-only
            // reply would format to "" — never paste nothing.
            if (polish.IsPolished && TextProcessor.Format(polish.Text, tone) is { Length: > 0 } formatted)
                finalText = formatted;
            // The reason only — never the text or the key.
            DiagnosticLog.Write($"AIPolish {polish.LogLabel} {polish.Milliseconds}ms context={previous.Count} changed={(finalText != processed).ToString().ToLowerInvariant()}");
            return finalText;
        }
        catch (Exception ex)
        {
            DiagnosticLog.Write($"AIPolish fallback(error) {ex.GetType().Name}");
            return processed;
        }
    }

    /// After a paste: remember the result for the next dictation's context (same app only).
    private void RememberForPolish(string pasted, string? targetApp)
    {
        if (_aiPolish) _polishContext.Append(pasted, targetApp);
    }

    /// The terminal pill stays for the usual 1 s, then the ONE "balance used up" pill for 3 s, then
    /// hides — when a reply emptied the balance. One timer chain, so a new recording cancels it.
    private bool TryShowPolishUsedUpAfterPaste()
    {
        bool show = AIPolishGate.ShouldShowUsedUp(_polishUsedUpPending, _polishUsage.Balance);
        _polishUsedUpPending = false;   // shown now, or stale (topped up since): either way it's done
        if (!show) return false;
        _hudResetTimer?.Stop();
        _hudResetTimer = new DispatcherTimer { Interval = AppTimings.HudResetDelay };
        _hudResetTimer.Tick += (_, _) =>
        {
            _hudResetTimer?.Stop();
            if (HudState.IsBusy) return; // a new recording took the pill
            ShowError(AIPolishUsageStore.BalanceUsedUpMessage);
        };
        _hudResetTimer.Start();
        return true;
    }

    // ---- renders (--settings-render aipolish-*) ----

    /// Stages the AI Polish card for a screenshot. Never touches the real key file or balance.
    public void EnterAiPolishPreviewState(string state)
    {
        _aiPolishPreview = true;
        (_apiKeyHint, _aiPolish, _polishBalance, _polishLastTopUp, _polishTotals) = state switch
        {
            "aipolish-nokey" => ((string?)null, false, 0.0, 0.0, new AIPolishUsageStore.Totals()),
            "aipolish-zero" => ("••••0000", true, 0.0, 0.0, new AIPolishUsageStore.Totals()),
            "aipolish-usedup" => ("••••0000", true, 0.0, 5.0, new AIPolishUsageStore.Totals(0.0412, 412, 5.0, 50_000)),
            _ => ("••••0000", true, 3.20, 5.0, new AIPolishUsageStore.Totals(0.00009, 1, 1.80, 18_000)), // aipolish-on / -revealed
        };
        RaiseAiPolishFlags();
    }
}
