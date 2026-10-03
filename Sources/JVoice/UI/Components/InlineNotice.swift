import SwiftUI

/// One short line under a Settings control explaining why an entry was not
/// taken (a shortcut already in use, a custom word turned away, an app that
/// could not be found): a `.caption` secondary line led by an orange mark, so it
/// reads as a warning (the one meaningful hue).
struct InlineNotice: View {
    let text: String
    let theme: Theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text(text)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
