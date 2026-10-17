using System.Text;

namespace JVoice.Core.AIPolish;

/// <summary>
/// Where the user's Anthropic key lives: ONE file holding the key ENCRYPTED by a protector the app
/// supplies — on Windows DPAPI (<c>ProtectedData</c>, <c>DataProtectionScope.CurrentUser</c>, with
/// <see cref="Entropy"/>), so only the same Windows user on the same machine can decrypt it, and no
/// prompt is ever shown. The app keeps it in <c>%LOCALAPPDATA%\JVoice\anthropic-api-key.bin</c> (Local,
/// not Roaming: a DPAPI blob is useless on another machine anyway). Never in settings JSON, a log,
/// history or the clipboard. Written via a temp file + replace; the hint ("••••abcd") is computed
/// from the stored key.
///
/// The protector is injected so the file handling is testable anywhere (tests on Windows also run it
/// with the real DPAPI).
/// </summary>
public sealed class ApiKeyStore
{
    /// <summary>App-specific DPAPI entropy: another program running as the same user can't decrypt the
    /// blob with a bare <c>Unprotect</c> call without also knowing this.</summary>
    public static readonly byte[] Entropy = Encoding.UTF8.GetBytes("JVoice.AIPolish.AnthropicApiKey.v1");

    public const string FileName = "anthropic-api-key.bin";

    private readonly string _path;
    private readonly Func<byte[], byte[]> _protect;
    private readonly Func<byte[], byte[]> _unprotect;

    public ApiKeyStore(string path, Func<byte[], byte[]> protect, Func<byte[], byte[]> unprotect)
    {
        _path = path;
        _protect = protect;
        _unprotect = unprotect;
    }

    public string FilePath => _path;

    /// <summary>The saved key, or null (no file, or it can't be decrypted — another user/machine).</summary>
    public string? Read()
    {
        try
        {
            if (!File.Exists(_path)) return null;
            byte[] clear = _unprotect(File.ReadAllBytes(_path));
            string key = Encoding.UTF8.GetString(clear).Trim();
            Array.Clear(clear);
            return key.Length == 0 ? null : key;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Saves <paramref name="key"/> (trimmed), replacing any saved one. False for a blank key
    /// or when it couldn't be written.</summary>
    public bool Save(string key)
    {
        string trimmed = key.Trim();
        if (trimmed.Length == 0) return false;
        string tmp = _path + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            byte[] clear = Encoding.UTF8.GetBytes(trimmed);
            byte[] blob = _protect(clear);
            Array.Clear(clear);
            File.WriteAllBytes(tmp, blob);
            File.Move(tmp, _path, overwrite: true);
            return true;
        }
        catch
        {
            try { File.Delete(tmp); } catch { /* best effort */ }
            return false;
        }
    }

    /// <summary>Deletes the key. True when no key is left (deleting nothing is fine).</summary>
    public bool Delete()
    {
        try
        {
            if (File.Exists(_path)) File.Delete(_path);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>"••••abcd" while a key is saved, else null.</summary>
    public string? SavedHint() => Read() is { } key ? Hint(key) : null;

    public static string Hint(string key) => "••••" + (key.Length <= 4 ? key : key[^4..]);
}
