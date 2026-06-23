using SkiaSharp;

namespace JVoice.Tools.GenerateIcon;

/// Port of scripts/generate-icon.swift geometry to SkiaSharp 3.x. Draws the
/// squircle-"J" app icon (multi-size .ico) plus the three tray glyphs
/// (all white — black & white theme: J / mic / waveform) into windows/JVoice.App/Assets.
///
/// Uses SKFont + SKCanvas.DrawText + SKFont.MeasureText (SkiaSharp 3.x dropped the
/// 2.x SKPaint text members the original plan snippet assumed).
internal static class Program
{
    private static int Main(string[] args)
    {
        string assets = args.Length > 0
            ? args[0]
            : Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "JVoice.App", "Assets"));
        Directory.CreateDirectory(assets);

        int[] sizes = { 16, 32, 48, 64, 128, 256 };
        var pngs = new List<byte[]>();
        foreach (int px in sizes)
            pngs.Add(EncodePng(RenderAppIcon(px)));
        File.WriteAllBytes(Path.Combine(assets, "JVoice.ico"), BuildIco(sizes, pngs));
        Console.WriteLine($"wrote JVoice.ico ({string.Join(",", sizes)})");

        File.WriteAllBytes(Path.Combine(assets, "tray-idle.png"),         EncodePng(RenderTrayGlyph(32, "J", SKColors.White, SKFontStyleWeight.Bold)));
        File.WriteAllBytes(Path.Combine(assets, "tray-recording.png"),    EncodePng(RenderTrayMic(32)));
        File.WriteAllBytes(Path.Combine(assets, "tray-transcribing.png"), EncodePng(RenderTrayWaveform(32)));
        Console.WriteLine("wrote tray-idle / tray-recording / tray-transcribing png");
        return 0;
    }

    private static byte[] EncodePng(SKBitmap bmp)
    {
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }

    // ---- App icon: faithful port of generate-icon.swift render(px:) ----
    private static SKBitmap RenderAppIcon(int px)
    {
        var bmp = new SKBitmap(px, px, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var canvas = new SKCanvas(bmp);
        canvas.Clear(SKColors.Transparent);

        float S = px;
        float shapeSide = MathF.Round(S * 0.805f);
        float o = MathF.Round((S - shapeSide) / 2f);
        var rect = new SKRect(o, o, o + shapeSide, o + shapeSide);
        float radius = shapeSide * 0.2237f;

        // Background squircle: vertical gradient top #1C1C1E -> bottom #0A0A0A.
        using (var bg = new SKPaint { IsAntialias = true })
        {
            bg.Shader = SKShader.CreateLinearGradient(
                new SKPoint(rect.MidX, rect.Top),
                new SKPoint(rect.MidX, rect.Bottom),
                new[] { new SKColor(0x1C, 0x1C, 0x1E), new SKColor(0x0A, 0x0A, 0x0A) },
                new[] { 0f, 1f },
                SKShaderTileMode.Clamp);
            canvas.DrawRoundRect(rect, radius, radius, bg);
        }

        // Inner glass edge: white@5%, inset shapeSide*0.012, lineWidth max(1, S*0.004).
        using (var edge = new SKPaint { IsAntialias = true, Style = SKPaintStyle.Stroke })
        {
            float inset = shapeSide * 0.012f;
            edge.StrokeWidth = MathF.Max(1f, S * 0.004f);
            edge.Color = new SKColor(0xFF, 0xFF, 0xFF, (byte)Math.Round(0.05 * 255));
            var inner = new SKRect(rect.Left + inset, rect.Top + inset, rect.Right - inset, rect.Bottom - inset);
            canvas.DrawRoundRect(inner, radius, radius, edge);
        }

        // "J" glyph: weight Black, size shapeSide*0.60, fill #EDEDF2, glow white@30% blur shapeSide*0.035.
        using var typeface = SKTypeface.FromFamilyName(
            "Segoe UI", SKFontStyleWeight.Black, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright)
            ?? SKTypeface.Default;
        using var font = new SKFont(typeface, shapeSide * 0.60f);

        const string glyph = "J";
        font.MeasureText(glyph, out SKRect b);
        float drawX = rect.MidX - (b.Left + b.Width / 2f);
        float drawY = rect.MidY - (b.Top + b.Height / 2f);

        using (var glow = new SKPaint { IsAntialias = true, Color = new SKColor(0xFF, 0xFF, 0xFF, (byte)Math.Round(0.30 * 255)) })
        {
            glow.ImageFilter = SKImageFilter.CreateBlur(shapeSide * 0.035f, shapeSide * 0.035f);
            canvas.DrawText(glyph, drawX, drawY, font, glow);
        }
        using (var glyphPaint = new SKPaint { IsAntialias = true, Color = new SKColor(0xED, 0xED, 0xF2) })
        {
            canvas.DrawText(glyph, drawX, drawY, font, glyphPaint);
        }
        canvas.Flush();
        return bmp;
    }

    // ---- Tray recording: mic; transcribing: waveform. White (monochrome). Vector glyphs (no font). ----
    private static SKBitmap RenderTrayMic(int px)
    {
        var bmp = NewTransparent(px);
        using var canvas = new SKCanvas(bmp);
        var white = SKColors.White;
        using var fill = new SKPaint { IsAntialias = true, Color = white, Style = SKPaintStyle.Fill };
        using var stroke = new SKPaint { IsAntialias = true, Color = white, Style = SKPaintStyle.Stroke, StrokeWidth = px * 0.07f, StrokeCap = SKStrokeCap.Round };
        float cx = px / 2f;
        float bw = px * 0.30f, bh = px * 0.42f, bt = px * 0.16f;
        var body = new SKRect(cx - bw / 2, bt, cx + bw / 2, bt + bh);
        canvas.DrawRoundRect(body, bw / 2, bw / 2, fill);
        using (var arc = new SKPath())
        {
            float r = px * 0.26f;
            arc.AddArc(new SKRect(cx - r, bt + bh * 0.30f, cx + r, bt + bh * 0.30f + 2 * r), 20, 140);
            canvas.DrawPath(arc, stroke);
        }
        canvas.DrawLine(cx, bt + bh + px * 0.10f, cx, px * 0.84f, stroke);
        canvas.DrawLine(cx - px * 0.13f, px * 0.84f, cx + px * 0.13f, px * 0.84f, stroke);
        canvas.Flush();
        return bmp;
    }

    private static SKBitmap RenderTrayWaveform(int px)
    {
        var bmp = NewTransparent(px);
        using var canvas = new SKCanvas(bmp);
        var white = SKColors.White;
        using var p = new SKPaint { IsAntialias = true, Color = white, Style = SKPaintStyle.Stroke, StrokeWidth = px * 0.09f, StrokeCap = SKStrokeCap.Round };
        float cx = px / 2f, mid = px / 2f;
        float[] hs = { 0.14f, 0.30f, 0.46f, 0.30f, 0.14f };
        float step = px * 0.16f;
        float x0 = cx - 2 * step;
        for (int i = 0; i < hs.Length; i++)
        {
            float x = x0 + i * step;
            float h = px * hs[i];
            canvas.DrawLine(x, mid - h, x, mid + h, p);
        }
        canvas.Flush();
        return bmp;
    }

    private static SKBitmap RenderTrayGlyph(int px, string glyph, SKColor color, SKFontStyleWeight weight)
    {
        var bmp = NewTransparent(px);
        using var canvas = new SKCanvas(bmp);
        using var tf = SKTypeface.FromFamilyName("Segoe UI", weight, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright) ?? SKTypeface.Default;
        using var font = new SKFont(tf, px * 0.78f);
        using var paint = new SKPaint { IsAntialias = true, Color = color };
        font.MeasureText(glyph, out SKRect b);
        float drawX = px / 2f - (b.Left + b.Width / 2f);
        float drawY = px / 2f - (b.Top + b.Height / 2f);
        canvas.DrawText(glyph, drawX, drawY, font, paint);
        canvas.Flush();
        return bmp;
    }

    private static SKBitmap NewTransparent(int px)
    {
        var bmp = new SKBitmap(px, px, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var c = new SKCanvas(bmp);
        c.Clear(SKColors.Transparent);
        return bmp;
    }

    // ---- Minimal ICO container: header + per-image directory + PNG-encoded frames. ----
    private static byte[] BuildIco(int[] sizes, List<byte[]> pngs)
    {
        using var ms = new MemoryStream();
        using var w = new BinaryWriter(ms);
        int count = sizes.Length;
        w.Write((short)0);        // reserved
        w.Write((short)1);        // type 1 = icon
        w.Write((short)count);    // image count
        int offset = 6 + 16 * count;
        for (int i = 0; i < count; i++)
        {
            int s = sizes[i];
            w.Write((byte)(s >= 256 ? 0 : s)); // width  (0 means 256)
            w.Write((byte)(s >= 256 ? 0 : s)); // height (0 means 256)
            w.Write((byte)0);     // palette
            w.Write((byte)0);     // reserved
            w.Write((short)1);    // color planes
            w.Write((short)32);   // bits per pixel
            w.Write(pngs[i].Length);
            w.Write(offset);
            offset += pngs[i].Length;
        }
        foreach (var png in pngs) w.Write(png);
        w.Flush();
        return ms.ToArray();
    }
}
