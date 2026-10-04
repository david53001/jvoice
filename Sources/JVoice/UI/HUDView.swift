import SwiftUI

struct HUDView: View {
    let state: HUDState
    var theme: Theme = .native
    var meter: AudioLevelMeter? = nil
    var onStop: (() -> Void)? = nil
    /// Morph from the pill on screen: the ONE capsule resizes to the new content (`HUDLayout.morph`)
    /// while the old content fades out and the new fades in. `HUDWindow` sets it only when a visible
    /// pill replaces another — the first show and the hide stay instant (latency contract).
    var animated = false

    var body: some View {
        Group {
            if state.isVisible {
                // Every pill reports its own size (the recording/transcribing row is 240 wide, a status
                // pill is as wide as its text), so the capsule hugs it at any panel size — and animates
                // between two pills' sizes instead of stretching to the panel.
                content
                    .fixedSize(horizontal: true, vertical: false)
                    .pillChrome()
            }
        }
        .animation(animated ? HUDLayout.morph : nil, value: state)
        // Bottom-anchored: while the panel is briefly bigger than the new capsule (`HUDWindow.update`),
        // the capsule's bottom edge and centre stay put.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .recording:
            RecordingPill(theme: theme, meter: meter, onStop: onStop)
                .transition(.opacity)
        case .downloadingModel(let downloaded, let total):
            DownloadingModelPill(downloaded: downloaded, total: total, theme: theme)
                .transition(.opacity)
        case .preparingModel:
            PreparingModelPill(theme: theme)
                .transition(.opacity)
        case .transcribing:
            TranscribingPill(theme: theme)
                .transition(.opacity)
        case .done, .copied, .error, .notice:
            StatusPill(state: state, theme: theme)
                .transition(.opacity)
        case .idle:
            EmptyView()
        }
    }
}

extension HUDState.AccentRole {
    /// The system colour this role means (the pill's one meaningful hue).
    var color: Color {
        switch self {
        case .secondary: return .secondary
        case .red:       return .red
        case .blue:      return .blue
        case .green:     return .green
        case .orange:    return .orange
        }
    }
}

// MARK: - Shared pill chrome

private extension View {
    /// The floating capsule: Liquid Glass on macOS 26, the `.hudWindow` material (behind-window blur,
    /// plus a 0.5 pt hairline — glass draws its own edge) before. No fill, border or glow of its own,
    /// and ONE soft shadow (`PillShadow`), drawn outside the capsule only so no text shadows through the
    /// translucent body. Applied once, around whichever content is showing, so a state change resizes
    /// this same capsule instead of swapping it. `HUDLayout.shadowPadding` keeps the shadow unclipped.
    func pillChrome() -> some View {
        self
            .frame(minHeight: HUDLayout.pillHeight)
            .modifier(PillMaterial())
            .background(PillShadow())
            .padding(HUDLayout.shadowPadding)
    }
}

/// A soft drop shadow OUTSIDE the capsule: a black capsule's shadow with the capsule itself cut away,
/// so it never darkens the translucent body. Being SwiftUI, it follows the capsule's size animation
/// (a window-server shadow would lag as a stale outline until re-traced).
private struct PillShadow: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.black)
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .mask(
                Rectangle()
                    .padding(-HUDLayout.shadowPadding)
                    .overlay(Capsule(style: .continuous).blendMode(.destinationOut))
                    .compositingGroup()
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct PillMaterial: ViewModifier {
    /// Dev only: `JVOICE_HUD_MATERIAL=1` shows the pre-macOS-26 material pill on macOS 26, so
    /// `--ui-preview` can screenshot the fallback on this Mac.
    static let forceFallback = ProcessInfo.processInfo.environment["JVOICE_HUD_MATERIAL"] == "1"
    private static let mask = VisualEffectBackground.capsuleMask(height: HUDLayout.pillHeight)

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), !Self.forceFallback {
            // The glass is a layer BEHIND the content, not the content's own effect: `.regular` glass
            // re-tints itself AND its content light over a white page (measured 2026-09-30), and glass
            // content gets a vibrancy that washes the red stop out to pink. `.clear` glass stays put,
            // and the Opacity backing on top of it carries the contrast (`UIOpacity`, `.pill`).
            content
                .background(OpacityBacking(surface: .pill, shape: Capsule()))
                .background(Color.clear.glassEffect(.clear, in: Capsule()))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(OpacityBacking(surface: .pill, shape: Capsule()))
            .background(VisualEffectBackground(material: .hudWindow, maskImage: Self.mask).clipShape(Capsule()))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: Design.hairlineWidth))
    }
}

// MARK: - J mark

private struct JMark: View {
    let theme: Theme
    var body: some View {
        Text("J")
            .font(.title3.weight(.heavy))
            .foregroundStyle(theme.barFill)
            .frame(width: 18)
            .accessibilityHidden(true)
    }
}

// MARK: - Waveform bars

/// Shared bar geometry: thin capsules that rest as a calm flat line (2 pt), never a row of dots.
private enum Bars {
    static let count = 15
    static let width: CGFloat = 3
    static let spacing: CGFloat = 2
    static let minHeight: CGFloat = 2
    static let rowHeight: CGFloat = 26

    /// Quiet bars sit at a secondary opacity and rise to full `.primary` with their height.
    static func opacity(height: CGFloat, maxHeight: CGFloat) -> Double {
        let t = max(0, min(1, (height - minHeight) / max(1, maxHeight - minHeight)))
        return 0.45 + 0.55 * Double(t)
    }
}

/// Recording: mic-reactive bars (driven by the live meter, with a subtle
/// per-bar oscillation so they look alive even at a steady level).
private struct ReactiveBars: View {
    @ObservedObject var meter: AudioLevelMeter
    let theme: Theme
    private let maxH: CGFloat = 26

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: Bars.spacing) {
                ForEach(0..<Bars.count, id: \.self) { i in
                    let h = height(i, t)
                    Capsule(style: .continuous)
                        .fill(theme.barFill.opacity(Bars.opacity(height: h, maxHeight: maxH)))
                        .frame(width: Bars.width, height: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Bars.rowHeight)
        }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let level = CGFloat(meter.level)                       // 0…1
        let osc = 0.55 + 0.45 * CGFloat(sin(t * 6 + Double(i) * 0.7)) // 0.1…1
        return Bars.minHeight + (maxH - Bars.minHeight) * level * osc
    }
}

/// Transcribing: a gentle, low-amplitude shimmer (no mic input during decode).
private struct ShimmerBars: View {
    let theme: Theme
    private let maxH: CGFloat = 10

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: Bars.spacing) {
                ForEach(0..<Bars.count, id: \.self) { i in
                    let h = height(i, t)
                    Capsule(style: .continuous)
                        .fill(theme.barFill.opacity(Bars.opacity(height: h, maxHeight: maxH) * 0.85))
                        .frame(width: Bars.width, height: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Bars.rowHeight)
        }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let wave = 0.5 + 0.5 * CGFloat(sin(t * 3 + Double(i) * 0.6))
        return Bars.minHeight + (maxH - Bars.minHeight) * wave
    }
}

// MARK: - Stop button

/// The red stop control: a continuous-cornered red square (radius 6) with a white stop glyph
/// (radius 2) — it alone says "recording", so the pill needs no label.
private struct StopButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.red)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(PanelPressableButtonStyle())
        .help("Stop recording")
        .accessibilityLabel("Stop recording")
    }
}

// MARK: - Recording pill

private struct RecordingPill: View {
    let theme: Theme
    let meter: AudioLevelMeter?
    let onStop: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            JMark(theme: theme)
            if let meter {
                ReactiveBars(meter: meter, theme: theme)
            } else {
                ShimmerBars(theme: theme) // defensive fallback
            }
            if let onStop {
                StopButton(action: onStop)
            } else {
                Color.clear.frame(width: 22)
            }
        }
        .padding(.horizontal, 16)
        // The Recording tour's anchor spans the whole capsule and declares its radius, so the tag's box
        // is a capsule hugging the pill (not a rectangle around it). This frame repeats `pillChrome`'s own
        // minimums, so layout is unchanged.
        .frame(minWidth: HUDLayout.pillMinWidth, minHeight: HUDLayout.pillHeight)
        .tourAnchor("pill.controls", cornerRadius: HUDLayout.pillCorner)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
    }
}

// MARK: - Transcribing pill

private struct TranscribingPill: View {
    let theme: Theme
    var body: some View {
        HStack(spacing: 14) {
            JMark(theme: theme)
            ShimmerBars(theme: theme)
            Color.clear.frame(width: 22) // keep bars centered (no stop button)
        }
        .padding(.horizontal, 16)
        .frame(minWidth: HUDLayout.pillMinWidth, minHeight: HUDLayout.pillHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
    }
}

// MARK: - Preparing-model pill (keeps a status icon + the live timer)

/// Shown while the Whisper model loads / does its first-ever CoreML compile
/// (~2¼ min for Large on first use). The ticking counter proves the app is
/// alive — a static pill reads as a hang and invites a force-quit that restarts
/// the compile from zero.
/// The network half of the model wait. Kept separate from `PreparingModelPill`
/// because a download and a CoreML compile fail for different reasons and want
/// different reassurance: this one is bounded and measurable, so it shows real
/// megabytes and a determinate bar rather than an elapsed timer.
private struct DownloadingModelPill: View {
    let downloaded: Int64
    let total: Int64
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(HUDState.AccentRole.blue.color)
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading Model")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(ModelDownloadProgress.label(downloaded: downloaded, total: total))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                ProgressBar(
                    fraction: ModelDownloadProgress.fraction(downloaded: downloaded, total: total),
                    theme: theme
                )
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Downloading model, \(ModelDownloadProgress.label(downloaded: downloaded, total: total))")
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let theme: Theme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(HUDState.AccentRole.blue.color)
                    .frame(width: geometry.size.width * fraction)
                    .animation(.smooth(duration: 0.3), value: fraction)
            }
        }
        .frame(width: 150, height: 4)
    }
}

private struct PreparingModelPill: View {
    let theme: Theme
    @State private var startDate = Date()

    private static func elapsed(_ start: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.body.weight(.semibold))
                .foregroundStyle(HUDState.AccentRole.blue.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Optimizing for Neural Engine")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                TimelineView(.periodic(from: startDate, by: 1)) { context in
                    Text("One-time per model — keep JVoice open · \(Self.elapsed(startDate, context.date))")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing model")
    }
}

// MARK: - Status pill (done / copied / error / notice)

private struct StatusPill: View {
    let state: HUDState
    let theme: Theme

    /// The text's own width, capped so the capsule never exceeds `HUDLayout.pillMaxWidth` (beyond it
    /// the text wraps, ≤ 2 lines). Measured, because a flexible `maxWidth` frame would stretch the
    /// capsule to whatever room the panel offers.
    private static let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
                                                weight: .medium)
    private static let maxTextWidth = HUDLayout.pillMaxWidth - 16 - 20 - 10 - 20   // padding · icon · gap · padding
    static func textWidth(_ text: String) -> CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return min(ceil(width) + 2, maxTextWidth)
    }

    var body: some View {
        let text: String = {
            if case .error(let message) = state, !message.isEmpty { return message }
            if case .notice(let message) = state { return message }
            return state.headline
        }()

        // The symbol alone, in the state's meaning colour (green done, orange error, secondary
        // notice) — no badge behind it.
        return HStack(spacing: 10) {
            Image(systemName: state.systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(state.accentRole.color)
                .frame(width: 20)
            Text(text)
                .font(.callout.weight(.medium))
                .frame(width: Self.textWidth(text), alignment: .leading)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
