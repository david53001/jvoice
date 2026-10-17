using System.Security.Cryptography;
using JVoice.Core.AIPolish;
using Xunit;

namespace JVoice.Tests;

/// The key store with the REAL protector the app uses (DPAPI, CurrentUser + JVoice's entropy) — the
/// same three calls as JVoice.App/AIPolish/DpapiKeyProtector. Windows-only: CI runs it on windows-latest.
public class AIPolishDpapiTests
{
    private static byte[] Protect(byte[] b) => ProtectedData.Protect(b, ApiKeyStore.Entropy, DataProtectionScope.CurrentUser);
    private static byte[] Unprotect(byte[] b) => ProtectedData.Unprotect(b, ApiKeyStore.Entropy, DataProtectionScope.CurrentUser);

    [Fact]
    public void TheKey_RoundTripsThroughDpapi_AndIsNeverOnDiskInTheClear()
    {
        if (!OperatingSystem.IsWindows()) return;
        string dir = Path.Combine(Path.GetTempPath(), "jvoice-dpapi-" + Guid.NewGuid().ToString("N"));
        var store = new ApiKeyStore(Path.Combine(dir, ApiKeyStore.FileName), Protect, Unprotect);
        try
        {
            Assert.True(store.Save(AIPolishTests.FakeKey));
            Assert.Equal(AIPolishTests.FakeKey, store.Read());
            Assert.Equal("••••0000", store.SavedHint());
            byte[] onDisk = File.ReadAllBytes(store.FilePath);
            Assert.DoesNotContain(AIPolishTests.FakeKey, System.Text.Encoding.UTF8.GetString(onDisk));
            Assert.DoesNotContain(AIPolishTests.FakeKey, System.Text.Encoding.Unicode.GetString(onDisk));

            // Without JVoice's entropy the blob does not decrypt (another program can't just Unprotect it).
            Assert.ThrowsAny<CryptographicException>(() => ProtectedData.Unprotect(onDisk, null, DataProtectionScope.CurrentUser));

            // A store whose protector can't decrypt reads as "no key" instead of throwing.
            var foreign = new ApiKeyStore(store.FilePath, Protect, b => ProtectedData.Unprotect(b, [1, 2, 3], DataProtectionScope.CurrentUser));
            Assert.Null(foreign.Read());
        }
        finally
        {
            try { Directory.Delete(dir, recursive: true); } catch (IOException) { }
        }
    }
}
