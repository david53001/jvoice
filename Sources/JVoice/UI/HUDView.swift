import SwiftUI

struct HUDView: View {
    let state: HUDState
    var theme: Theme = .dark
    var meter: AudioLevelMeter? = nil
    var onStop: (() -> Void)? = nil

    var body: some View {
        switch state {
        case .recording:
            RecordingPill(theme: theme, meter: meter, onStop: onStop)
        case .preparingModel:
            PreparingModelPill(theme: theme)
        case .transcribing:
            TranscribingPill(theme: theme)
        case .done, .error:
            StatusPill(state: state, theme: theme)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Shared pill chrome

private extension View {
    /// Monochrome pill body + soft, even glow that fully fades within the
    /// surrounding glow padding (no square clip).
    func pillChrome(theme: Theme, minWidth: CGFloat = HUDLayout.pillMinWidth, maxWidth: CGFloat? = nil) -> some View {
        self
            .frame(minWidth: minWidth,
                   maxWidth: maxWidth,
                   minHeight: HUDLayout.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: HUDLayout.pillCorner, style: .continuous)
                    .fill(theme.pillBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HUDLayout.pillCorner, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
            .shadow(color: theme.pillGlow, radius: 16)
            .shadow(color: theme.pillGlow.opacity(0.6), radius: 28)
            .shadow(color: theme.pillDropShadow, radius: 12, x: 0, y: 6)
            .padding(HUDLayout.glowPadding)
    }
}

// MARK: - J mark

private struct JMark: View {
    let theme: Theme
    var body: some View {
        Text("J")
            .font(.system(size: 22, weight: .heavy))
            .foregroundStyle(theme.barFill)
            .frame(width: 18)
            .accessibilityHidden(true)
    }
}

// MARK: - Waveform bars

/// Recording: mic-reactive bars (driven by the live meter, with a subtle
/// per-bar oscillation so they look alive even at a steady level).
private struct ReactiveBars: View {
    @ObservedObject var meter: AudioLevelMeter
    let theme: Theme
    let barCount = 15
    private let minH: CGFloat = 4
    private let maxH: CGFloat = 26

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(theme.barFill)
                        .frame(width: 3, height: height(i, t))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: maxH)
        }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let level = CGFloat(meter.level)                       // 0…1
        let osc = 0.55 + 0.45 * CGFloat(sin(t * 6 + Double(i) * 0.7)) // 0.1…1
        return minH + (maxH - minH) * level * osc
    }
}

/// Transcribing: a gentle, low-amplitude shimmer (no mic input during decode).
private struct ShimmerBars: View {
    let theme: Theme
    let barCount = 15
    private let minH: CGFloat = 4
    private let maxH: CGFloat = 11

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(theme.barFill.opacity(0.85))
                        .frame(width: 3, height: height(i, t))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
        }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let wave = 0.5 + 0.5 * CGFloat(sin(t * 3 + Double(i) * 0.6))
        return minH + (maxH - minH) * wave
    }
}

// MARK: - Stop button

private struct StopButton: View {
    let theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.barFill.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.barFill.opacity(0.45), lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.barFill)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(PanelPressableButtonStyle())
        .accessibilityLabel("Stop recording")
    }
}

// MARK: - Bottom label

private struct PillLabel: View {
    let text: String
    let theme: Theme
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 7, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(theme.textMuted)
    }
}

// MARK: - Recording pill

private struct RecordingPill: View {
    let theme: Theme
    let meter: AudioLevelMeter?
    let onStop: (() -> Void)?

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                JMark(theme: theme)
                if let meter {
                    ReactiveBars(meter: meter, theme: theme)
                } else {
                    ShimmerBars(theme: theme) // defensive fallback
                }
                if let onStop {
                    StopButton(theme: theme, action: onStop)
                } else {
                    Color.clear.frame(width: 22)
                }
            }
            .padding(.horizontal, 16)

            VStack {
                Spacer()
                PillLabel(text: "Recording", theme: theme)
                    .padding(.bottom, 6)
            }
        }
        .pillChrome(theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
    }
}

// MARK: - Transcribing pill

private struct TranscribingPill: View {
    let theme: Theme
    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                JMark(theme: theme)
                ShimmerBars(theme: theme)
                Color.clear.frame(width: 22) // keep bars centered (no stop button)
            }
            .padding(.horizontal, 16)

            VStack {
                Spacer()
                PillLabel(text: "Transcribing", theme: theme)
                    .padding(.bottom, 6)
            }
        }
        .pillChrome(theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
    }
}

// MARK: - Preparing-model pill (keeps a status icon + the live timer)

/// Shown while the Whisper model loads / does its first-ever CoreML compile
/// (~2¼ min for Large on first use). The ticking counter proves the app is
/// alive — a static pill reads as a hang and invites a force-quit that restarts
/// the compile from zero.
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preparing Model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                TimelineView(.periodic(from: startDate, by: 1)) { context in
                    Text("One-time setup — keep JVoice open · \(Self.elapsed(startDate, context.date))")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .pillChrome(theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing model")
    }
}

// MARK: - Status pill (done / error)

private struct StatusPill: View {
    let state: HUDState
    let theme: Theme

    var body: some View {
        let text: String = {
            if case .error(let message) = state, !message.isEmpty { return message }
            return state.headline
        }()

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.barFill.opacity(0.12))
                    .overlay(Circle().strokeBorder(theme.barFill.opacity(0.30), lineWidth: 1))
                    .frame(width: 28, height: 28)
                Image(systemName: state.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .pillChrome(theme: theme, maxWidth: 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
