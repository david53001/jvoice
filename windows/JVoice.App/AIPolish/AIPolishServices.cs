using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using JVoice.App.Platform;
using JVoice.Core.AIPolish;

namespace JVoice.App.AIPolish;

/// <summary>
/// The real transport: ONE shared <see cref="HttpClient"/> with every store off — no cookies, no
/// credentials (the system proxy is still honoured, but never handed the user's Windows credentials),
/// no redirects (a redirect would re-send the <c>x-api-key</c> header to wherever it points), no
/// cache (HttpClient has none). The key exists only in the one request's header. Timeouts are the
/// caller's (the client's deadline + its token), so <c>HttpClient.Timeout</c> is infinite.
/// </summary>
public sealed class HttpPolishTransport : IPolishTransport
{
    public static readonly HttpPolishTransport Shared = new();

    private readonly HttpClient _http;

    private HttpPolishTransport()
    {
        var handler = new SocketsHttpHandler
        {
            UseCookies = false,
            AllowAutoRedirect = false,
            Credentials = null,
            DefaultProxyCredentials = null,
            PreAuthenticate = false,
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            ConnectTimeout = TimeSpan.FromSeconds(10),
        };
        _http = new HttpClient(handler, disposeHandler: true) { Timeout = Timeout.InfiniteTimeSpan };
    }

    public async Task<PolishHttpResponse> SendAsync(PolishHttpRequest request, CancellationToken ct)
    {
        using var message = new HttpRequestMessage(HttpMethod.Post, request.Url)
        {
            Content = new StringContent(request.Body, Encoding.UTF8, "application/json"),
        };
        foreach (var (name, value) in request.Headers)
        {
            if (string.Equals(name, "content-type", StringComparison.OrdinalIgnoreCase)) continue; // set by the content
            message.Headers.TryAddWithoutValidation(name, value);
        }
        // StringContent appends "; charset=utf-8"; send exactly what the API documents.
        message.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        using var response = await _http.SendAsync(message, HttpCompletionOption.ResponseContentRead, ct).ConfigureAwait(false);
        string body = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        return new PolishHttpResponse((int)response.StatusCode, body);
    }
}

/// <summary>DPAPI for the key file: CurrentUser scope + JVoice's entropy. No prompt, ever.</summary>
public static class DpapiKeyProtector
{
    public static byte[] Protect(byte[] clear) =>
        ProtectedData.Protect(clear, ApiKeyStore.Entropy, DataProtectionScope.CurrentUser);

    public static byte[] Unprotect(byte[] blob) =>
        ProtectedData.Unprotect(blob, ApiKeyStore.Entropy, DataProtectionScope.CurrentUser);

    /// <summary>The app's key store (<c>%LOCALAPPDATA%\JVoice\anthropic-api-key.bin</c>).</summary>
    public static ApiKeyStore CreateStore() => new(PlatformPaths.ApiKeyFile, Protect, Unprotect);
}
