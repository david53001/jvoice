import SwiftUI

struct HUDView: View {
    let state: HUDState
    var onStop: (() -> Void)? = nil

    var body: some View {
        switch state {
        case .recording:
            RecordingPill(onStop: onStop)
        case .preparingModel:
            PreparingModelPill()
        case .transcribing:
            TranscribingPill()
        case .done, .error:
            StatusPill(state: state)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Shared background

private func pillBackground(borderColor: Color) -> some View {
    RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color(red: 0.027, green: 0.027, blue: 0.055))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor.opacity(0.22), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [borderColor.opacity(0.06), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
        )
        .shadow(color: borderColor.opacity(0.18), radius: 16)
        .shadow(color: borderColor.opacity(0.07), radius: 32)
}

// MARK: - OrbitalRing

private struct PulseModifier: ViewModifier {
    @State private var scale: CGFloat = 0.9

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    scale = 1.05
                }
            }
    }
}

private struct OrbitalRing: View {
    let ringColor: Color
    let iconName: String

    var body: some View {
        ZStack {
            // Pulsing aura behind the ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [ringColor.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 18
                    )
                )
                .frame(width: 36, height: 36)
                .modifier(PulseModifier())

            // Spinning arc
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                let degrees = (phase.truncatingRemainder(dividingBy: 4.0) / 4.0) * 360.0
                Circle()
                    .trim(from: 0.0, to: 0.28)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(degrees))
                    .shadow(color: ringColor.opacity(0.85), radius: 3)
                    .shadow(color: ringColor.opacity(0.4), radius: 6)
            }

            // Fixed center icon
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ringColor)
                .shadow(color: ringColor.opacity(0.6), radius: 4)
                .shadow(color: ringColor.opacity(0.25), radius: 10)
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - StopButton

private struct StopButton: View {
    let action: () -> Void

    private static let stopRed = Color(red: 1.0, green: 0.376, blue: 0.376)

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Self.stopRed.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Self.stopRed.opacity(0.30), lineWidth: 1)
                    )
                    .shadow(color: Self.stopRed.opacity(0.20), radius: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.stopRed)
                    .shadow(color: Self.stopRed.opacity(0.80), radius: 3)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(PanelPressableButtonStyle())
        .accessibilityLabel("Stop recording")
    }
}

// MARK: - RecordingPill

private struct RecordingPill: View {
    let onStop: (() -> Void)?

    private static let accent = Color(red: 0.290, green: 0.620, blue: 1.000)
    private static let textColor = Color(red: 0.820, green: 0.910, blue: 1.000)
    private static let subColor = accent.opacity(0.55)

    var body: some View {
        HStack(spacing: 10) {
            OrbitalRing(ringColor: Self.accent, iconName: "mic.fill")

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.textColor)
                    .shadow(color: Self.accent.opacity(0.55), radius: 6)
                    .shadow(color: Self.accent.opacity(0.20), radius: 18)
                Text("Listening…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Self.subColor)
            }

            Spacer(minLength: 0)

            if let onStop {
                StopButton(action: onStop)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: HUDLayout.hudPillSize.width, minHeight: HUDLayout.hudPillSize.height)
        .background { pillBackground(borderColor: Self.accent) }
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(32)
    }
}

// MARK: - PreparingModelPill

/// Shown when a dictation has to wait for the Whisper model to load (or its
/// first-ever CoreML specialization — measured ~2¼ min for large-v3_turbo on
/// an M3; the OS caches the result per bundle ID, so it only happens once).
/// The ticking elapsed counter proves the app is alive: a static pill reads
/// as a hang and invites a force-quit, which restarts the ANE compile from
/// zero and makes the wait endless.
private struct PreparingModelPill: View {
    private static let accent = Color(red: 0.502, green: 0.376, blue: 1.000)
    private static let textColor = Color(red: 0.792, green: 0.733, blue: 1.000)
    private static let subColor = accent.opacity(0.62)

    @State private var startDate = Date()

    private static func elapsedText(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        HStack(spacing: 10) {
            OrbitalRing(ringColor: Self.accent, iconName: "gearshape.2")

            VStack(alignment: .leading, spacing: 2) {
                Text("Preparing Model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.textColor)
                    .shadow(color: Self.accent.opacity(0.55), radius: 6)
                    .shadow(color: Self.accent.opacity(0.20), radius: 18)
                TimelineView(.periodic(from: startDate, by: 1)) { context in
                    Text("One-time setup — keep JVoice open · \(Self.elapsedText(from: startDate, to: context.date))")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Self.subColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: HUDLayout.hudPillSize.width, minHeight: HUDLayout.hudPillSize.height)
        .background { pillBackground(borderColor: Self.accent) }
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing model")
    }
}

// MARK: - TranscribingPill

private struct TranscribingPill: View {
    private static let accent = Color(red: 0.000, green: 0.831, blue: 0.878)
    private static let textColor = Color(red: 0.627, green: 0.941, blue: 0.969)
    private static let subColor = accent.opacity(0.55)

    var body: some View {
        HStack(spacing: 10) {
            OrbitalRing(ringColor: Self.accent, iconName: "waveform.path")

            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.textColor)
                    .shadow(color: Self.accent.opacity(0.55), radius: 6)
                    .shadow(color: Self.accent.opacity(0.20), radius: 18)
                Text("Processing…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Self.subColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: HUDLayout.hudPillSize.width, minHeight: HUDLayout.hudPillSize.height)
        .background { pillBackground(borderColor: Self.accent) }
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
    }
}

// MARK: - StatusPill

private struct StatusPill: View {
    let state: HUDState

    private var accent: Color {
        switch state {
        case .done:  return Color(red: 0.431, green: 0.906, blue: 0.718)
        case .error: return Color(red: 0.980, green: 0.627, blue: 0.376)
        default:     return .secondary
        }
    }

    private var textColor: Color {
        switch state {
        case .done:  return Color(red: 0.694, green: 0.988, blue: 0.718)
        case .error: return Color(red: 1.000, green: 0.820, blue: 0.627)
        default:     return .white
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .overlay(Circle().strokeBorder(accent.opacity(0.30), lineWidth: 1))
                    .shadow(color: accent.opacity(0.22), radius: 6)
                    .frame(width: 28, height: 28)
                Image(systemName: state.systemImageName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.70), radius: 4)
            }

            Text(state.headline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .shadow(color: accent.opacity(0.55), radius: 6)
                .shadow(color: accent.opacity(0.20), radius: 18)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: HUDLayout.hudPillSize.width, minHeight: HUDLayout.hudPillSize.height)
        .background { pillBackground(borderColor: accent) }
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.headline)
    }
}
