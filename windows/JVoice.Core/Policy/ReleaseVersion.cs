using System.Globalization;

namespace JVoice.Core.Policy;

/// A tolerant numeric version, used by the in-app updater to compare the running build against a
/// GitHub release tag. Windows-only feature; no macOS counterpart (like the other Policy update
/// helpers). Parses the shapes a release tag realistically takes: an optional leading tag prefix
/// (a bare `v`/`V`, or a mono-repo product prefix like `windows-` — this one repo tags the Windows
/// line `windows-v1.2.3` so it can coexist with the macOS `v1.2.3`), two to four dotted numeric
/// components, and trailing SemVer pre-release/build metadata (`-rc.1`, `+build`) which is ignored.
/// Anything without a numeric component (e.g. `windows-latest`) fails to parse — the caller treats a
/// parse failure as "no update" so a weird tag can never trigger a prompt.
public readonly struct ReleaseVersion : IComparable<ReleaseVersion>, IEquatable<ReleaseVersion>
{
    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public int Build { get; }

    public ReleaseVersion(int major, int minor = 0, int patch = 0, int build = 0)
    {
        Major = major;
        Minor = minor;
        Patch = patch;
        Build = build;
    }

    public static bool TryParse(string? raw, out ReleaseVersion version)
    {
        version = default;
        if (string.IsNullOrWhiteSpace(raw)) return false;

        string s = raw.Trim();

        // Skip any leading tag prefix that isn't part of the number: a bare `v`/`V`, and also a
        // mono-repo product prefix like `windows-` (so `v1.2.3` and `windows-v1.2.3` both reduce to
        // `1.2.3`). We advance to the first digit; a tag with no digit at all (e.g. `windows-latest`)
        // has nothing to advance to and falls through to the "no numeric component" failure below.
        int start = 0;
        while (start < s.Length && !char.IsAsciiDigit(s[start])) start++;
        s = s[start..];

        // Drop SemVer pre-release / build metadata: everything from the first '-' or '+'.
        int cut = s.IndexOfAny(new[] { '-', '+' });
        if (cut >= 0) s = s[..cut];

        string[] parts = s.Split('.');
        var nums = new int[4];
        int parsed = 0;
        foreach (var part in parts)
        {
            if (parsed >= 4) break;
            // Stop at the first non-integer segment (e.g. "1.2.x" → 1.2.0) rather than failing:
            // whatever leading numeric prefix exists still orders correctly.
            if (!int.TryParse(part, NumberStyles.None, CultureInfo.InvariantCulture, out int n)) break;
            nums[parsed++] = n;
        }

        if (parsed == 0) return false; // no leading integer component → not a version
        version = new ReleaseVersion(nums[0], nums[1], nums[2], nums[3]);
        return true;
    }

    public int CompareTo(ReleaseVersion other)
    {
        int c = Major.CompareTo(other.Major); if (c != 0) return c;
        c = Minor.CompareTo(other.Minor); if (c != 0) return c;
        c = Patch.CompareTo(other.Patch); if (c != 0) return c;
        return Build.CompareTo(other.Build);
    }

    public bool Equals(ReleaseVersion other) => CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is ReleaseVersion v && Equals(v);
    public override int GetHashCode() => HashCode.Combine(Major, Minor, Patch, Build);
    public override string ToString() => $"{Major}.{Minor}.{Patch}.{Build}";
}
