using System.Diagnostics;
using JVoice.Core.Models;

namespace JVoice.Core.AIPolish;

/// <summary>One POST: the URL, the headers (incl. the key) and the JSON body.</summary>
public sealed record PolishHttpRequest(string Url, IReadOnlyList<KeyValuePair<string, string>> Headers, string Body)
{
    public string? Header(string name) =>
        Headers.FirstOrDefault(h => string.Equals(h.Key, name, StringComparison.OrdinalIgnoreCase)).Value;

    /// Never prints the key (a record's generated ToString would).
    public override string ToString() => $"POST {Url} ({Body.Length} chars)";
}

/// <summary>The raw reply: HTTP status and body text.</summary>
public sealed record PolishHttpResponse(int Status, string Body);

/// <summary>Sends one request and returns the raw reply. The app uses an <c>HttpClient</c> transport
/// with every store off (<c>JVoice.App/AIPolish/HttpPolishTransport</c>); tests inject a fake, so no
/// test ever touches the network. Throw <see cref="HttpRequestException"/> (or any exception) for a
/// network failure, <see cref="TimeoutException"/> for a transport timeout.</summary>
public interface IPolishTransport
{
    Task<PolishHttpResponse> SendAsync(PolishHttpRequest request, CancellationToken ct);
}

/// <summary>One polish attempt: the text to paste (the polished text, or the original on any
/// fallback), why, how long it took and what it cost.</summary>
public sealed record AIPolishResult(string Text, AIPolishOutcome Outcome, int Milliseconds, AIPolishUsage? Usage)
{
    public bool IsPolished => Outcome.IsPolished;

    /// <summary><c>ok</c> or <c>fallback(&lt;reason&gt;)</c> — the only part of a polish that is ever logged.</summary>
    public string LogLabel => Outcome.Fallback is { } f ? $"fallback({f.LogLabel})" : "ok";
}

/// <summary>
/// Sends a dictation to Claude under a HARD deadline on the whole attempt (key read + request +
/// reply). Port of the Mac's <c>AIPolishClient</c>: the deadline is a <c>Task.WhenAny</c> race against
/// a timer, so it wins even when the transport ignores cancellation (the paste is never held hostage).
///
/// Windows addition (Mac review: "a reply that arrives after the deadline was billed but isn't
/// subtracted"): when the deadline wins, the request is NOT cancelled — it is left to finish in the
/// background for up to <see cref="LateReplyCap"/>, and if a billed reply does arrive,
/// <c>onLateUsage</c> receives its usage so the balance still pays for it. Its text is never used.
/// </summary>
public sealed class AIPolishClient
{
    /// <summary>How long a reply that missed the deadline may still arrive (to be billed, not pasted).</summary>
    public static readonly TimeSpan LateReplyCap = TimeSpan.FromSeconds(30);

    private readonly IPolishTransport _transport;
    private readonly TimeSpan _deadline;

    public AIPolishClient(IPolishTransport transport, TimeSpan deadline)
    {
        _transport = transport;
        _deadline = deadline;
    }

    public async Task<AIPolishResult> PolishAsync(
        string text, IReadOnlyList<string> previous, ToneStyle mode, IReadOnlyList<string> vocabulary,
        Func<string?> apiKey, AIPolishOptions? options = null, CancellationToken ct = default,
        Action<AIPolishUsage>? onLateUsage = null)
    {
        options ??= AIPolishOptions.Standard;
        var clock = Stopwatch.StartNew();
        // The attempt's own token: the late-reply cap ends it eventually; the caller's cancellation (the
        // dictation was abandoned) ends it at once — but only until the race is decided. The coordinator
        // cancels a dictation's token on the NEXT press, and that must not kill a reply that already
        // missed the deadline and is still coming in to be billed.
        var attemptCts = new CancellationTokenSource();
        attemptCts.CancelAfter(_deadline + LateReplyCap);
        var token = attemptCts.Token;
        var forwardCancel = ct.Register(() => { try { attemptCts.Cancel(); } catch (ObjectDisposedException) { } });

        // Task.Run: the key read is synchronous file I/O + DPAPI and must be inside the deadline too.
        var attempt = Task.Run(() => AttemptAsync(text, previous, mode, vocabulary, apiKey, options, ct, token), CancellationToken.None);
        var timer = Task.Delay(_deadline, CancellationToken.None);
        var cancelled = Task.Delay(Timeout.Infinite, ct);

        var first = await Task.WhenAny(attempt, timer, cancelled).ConfigureAwait(false);
        forwardCancel.Dispose(); // decided: later cancellation of the dictation no longer reaches the request
        (AIPolishOutcome Outcome, AIPolishUsage? Usage) result;
        if (first == attempt)
        {
            result = await attempt.ConfigureAwait(false);
            attemptCts.Dispose();
        }
        else if (first == timer && !ct.IsCancellationRequested)
        {
            result = (AIPolishOutcome.Fail(FallbackKind.Timeout), null);
            _ = attempt.ContinueWith((Task<(AIPolishOutcome Outcome, AIPolishUsage? Usage)> t) =>
            {
                attemptCts.Dispose();
                if (t.Status == TaskStatus.RanToCompletion && t.Result.Usage is { } late)
                {
                    try { onLateUsage?.Invoke(late); } catch { /* billing bookkeeping must never throw into a pool thread */ }
                }
            }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        }
        else
        {
            attemptCts.Cancel();
            result = (AIPolishOutcome.Fail(FallbackKind.Cancelled), null);
            _ = attempt.ContinueWith(_ => attemptCts.Dispose(), TaskScheduler.Default);
        }
        // Observe the never-completing cancel waiter's exception when it does fire.
        _ = cancelled.ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted);

        int ms = (int)clock.ElapsedMilliseconds;
        string finalText = result.Outcome.Polished ?? text;
        return new AIPolishResult(finalText, result.Outcome, ms, result.Usage);
    }

    private async Task<(AIPolishOutcome Outcome, AIPolishUsage? Usage)> AttemptAsync(
        string text, IReadOnlyList<string> previous, ToneStyle mode, IReadOnlyList<string> vocabulary,
        Func<string?> apiKey, AIPolishOptions options, CancellationToken callerCt, CancellationToken token)
    {
        string? key;
        try { key = apiKey(); }
        catch { key = null; }
        if (string.IsNullOrEmpty(key)) return (AIPolishOutcome.Fail(FallbackKind.NoKey), null);

        var body = AIPolishRequest.Body(text, previous, mode, vocabulary, options);
        var request = AIPolishRequest.HttpRequest(body, key);
        try
        {
            var response = await _transport.SendAsync(request, token).ConfigureAwait(false);
            var outcome = AIPolishRequest.Outcome(response.Status, response.Body, text, previous);
            // Usage only from a 200: an error reply carries none and isn't billed.
            var usage = response.Status == 200 ? AIPolishRequest.Decode(response.Body)?.Usage : null;
            return (outcome, usage);
        }
        catch (OperationCanceledException) when (callerCt.IsCancellationRequested)
        {
            return (AIPolishOutcome.Fail(FallbackKind.Cancelled), null);
        }
        catch (OperationCanceledException)
        {
            return (AIPolishOutcome.Fail(FallbackKind.Timeout), null);
        }
        catch (TimeoutException)
        {
            return (AIPolishOutcome.Fail(FallbackKind.Timeout), null);
        }
        catch (Exception)
        {
            return (AIPolishOutcome.Fail(FallbackKind.Network), null);
        }
    }
}

/// <summary>The pure parts of the façade the coordinator and Settings call.</summary>
public static class AIPolishGate
{
    /// <summary>Dictations shorter than this many words go out unpolished: "ok", "thanks", "sounds
    /// good" have nothing to fix that is worth a round trip.</summary>
    public const int MinWords = 3;

    /// <summary>The app's deadline on the whole attempt (Mac <c>AppTimings.aiPolishTimeout</c>).</summary>
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(3.0);

    public static bool IsWorthPolishing(string text) =>
        text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length >= MinWords;

    /// <summary>What the coordinator does with a finished dictation, in the Mac's order: off → nothing
    /// (no log); at $0 → <c>skipped(balance)</c>; under 3 words → <c>skipped(short)</c>; else send.</summary>
    public static PolishStep Plan(bool enabled, double balance, string text) =>
        !enabled ? PolishStep.Off
        : !AIPolishUsageStore.ShouldPolish(enabled, hasKey: true, balance) ? PolishStep.SkipBalance
        : !IsWorthPolishing(text) ? PolishStep.SkipShort
        : PolishStep.Send;

    /// <summary>Show the ONE "used up" pill after this paste? Only while a reply emptied the balance AND
    /// it is still empty (a user who already topped up never sees a stale warning).</summary>
    public static bool ShouldShowUsedUp(bool pending, double balance) => pending && balance <= 0;
}

public enum PolishStep { Off, SkipBalance, SkipShort, Send }

/// <summary>Settings → Test Key: the outcome of one tiny request.</summary>
public enum KeyCheckKind { Works, InvalidKey, RateLimited, Unreachable, Failed }

public readonly record struct KeyCheck(KeyCheckKind Kind, string? Detail = null)
{
    /// <summary>Plain words for the Settings status line (never logged).</summary>
    public string Message => Kind switch
    {
        KeyCheckKind.Works => "Key works.",
        KeyCheckKind.InvalidKey => "Invalid key — Anthropic didn't accept it.",
        KeyCheckKind.RateLimited => "The key works, but Anthropic is rate-limiting it right now.",
        KeyCheckKind.Unreachable => "Couldn't reach Anthropic. Check your internet connection.",
        _ => Detail ?? "Anthropic returned an error.",
    };
}

public static class AIPolishKeyCheck
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);

    /// <summary>One tiny request (a 1-token reply) to see whether Anthropic accepts <paramref name="key"/>.</summary>
    public static async Task<KeyCheck> CheckAsync(string key, IPolishTransport transport)
    {
        var body = new System.Text.Json.Nodes.JsonObject
        {
            ["model"] = AIPolishRequest.DefaultModel,
            ["max_tokens"] = 1,
            ["thinking"] = new System.Text.Json.Nodes.JsonObject { ["type"] = "disabled" },
            ["messages"] = new System.Text.Json.Nodes.JsonArray(new System.Text.Json.Nodes.JsonObject
            {
                ["role"] = "user",
                ["content"] = "Hi",
            }),
        };
        var request = AIPolishRequest.HttpRequest(body, key);
        using var cts = new CancellationTokenSource(Timeout);
        var send = Task.Run(async () =>
        {
            try
            {
                var response = await transport.SendAsync(request, cts.Token).ConfigureAwait(false);
                return FromStatus(response.Status, response.Body);
            }
            catch
            {
                return new KeyCheck(KeyCheckKind.Unreachable);
            }
        });
        var first = await Task.WhenAny(send, Task.Delay(Timeout)).ConfigureAwait(false);
        return first == send ? await send.ConfigureAwait(false) : new KeyCheck(KeyCheckKind.Unreachable);
    }

    public static KeyCheck FromStatus(int status, string body)
    {
        switch (status)
        {
            case 200: return new KeyCheck(KeyCheckKind.Works);
            case 401: return new KeyCheck(KeyCheckKind.InvalidKey);
            case 429: return new KeyCheck(KeyCheckKind.RateLimited);
        }
        // Anthropic's own error message (e.g. "Your credit balance is too low…") — shown in Settings
        // only, never logged.
        string? detail = null;
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(body);
            if (doc.RootElement.ValueKind == System.Text.Json.JsonValueKind.Object
                && doc.RootElement.TryGetProperty("error", out var error) && error.ValueKind == System.Text.Json.JsonValueKind.Object
                && error.TryGetProperty("message", out var m) && m.ValueKind == System.Text.Json.JsonValueKind.String)
                detail = m.GetString();
        }
        catch (System.Text.Json.JsonException) { }
        if (!string.IsNullOrEmpty(detail))
        {
            string shortened = detail.Length > 160 ? detail[..160] : detail;
            return new KeyCheck(KeyCheckKind.Failed, $"Anthropic said ({status}): {shortened}");
        }
        return new KeyCheck(KeyCheckKind.Failed, $"Anthropic returned an error ({status}).");
    }
}
