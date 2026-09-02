//
//  WelcomeMessageBanner.swift
//  AppwinSupport
//
//  Welcome message: slate-200, 10px medium, as in the preview.
//  Wraps very long words with no spaces, so they do not overflow.
//

import SwiftUI

struct WelcomeMessageBanner: View {
    let message: String

    @Environment(\.appwinTheme) private var theme

    private let slate200 = Color(hex: 0xE2E8F0)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SolarIcon(kind: .infoCircle, color: theme.colors.textSecondary, size: 12)
                .padding(.top, 1)

            Text(softWrappedMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(slate200)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(slate200, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
