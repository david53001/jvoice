import SwiftUI

/// One short line under a Settings control explaining why an entry was not
/// taken (a shortcut already in use, a custom word turned away, an app that
/// could not be found). Same 10 pt caption as the Settings hints, one step
/// brighter and with a mark so it reads as feedback, still monochrome.
struct InlineNotice: View {
    let text: String
    let theme: Theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.circle")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10))
        .foregroundStyle(theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
