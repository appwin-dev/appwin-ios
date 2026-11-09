//
//  WelcomeMessageBanner.swift
//  AppwinSupport
//
//  Welcome message - Figma support-convo 40:6966: bg/low strip, info icon,
//  12pt text in text/secondary.
//  Wraps very long words with no spaces, so they do not overflow.
//

import SwiftUI

struct WelcomeMessageBanner: View {
    let message: String

    @Environment(\.appwinTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SolarIcon(kind: .infoCircle, color: theme.colors.textSecondary, size: 16)

            Text(softWrappedMessage)
                .font(.system(size: 12, weight: .regular))
                .lineSpacing(12 * 0.3)
                .foregroundColor(theme.colors.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appwinCard(padding: 16, cornerRadius: theme.radius.card, fill: AppwinTokens.surfaceMuted)
    }

    /// A zero-width space every ~12 characters inside space-free runs, which is
    /// what makes wrapping possible.
    private var softWrappedMessage: String {
        message.split(separator: " ", omittingEmptySubsequences: false).map { word in
            guard word.count > 12 else { return String(word) }
            var out = ""
            for (i, ch) in word.enumerated() {
                if i > 0 && i % 12 == 0 { out.append("\u{200B}") }
                out.append(ch)
            }
            return out
        }.joined(separator: " ")
    }
}
