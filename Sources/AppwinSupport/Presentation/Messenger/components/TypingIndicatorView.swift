//
//  TypingIndicatorView.swift
//  AppwinSupport
//
//  Three animated dots, mirroring the dashboard `TypingIndicator`.
//

import SwiftUI

struct TypingIndicatorView: View {
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    TypingDot(delay: Double(index) * 0.12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(AppwinTokens.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)
        }
        .accessibilityLabel("En train d'écrire")
    }
}

private struct TypingDot: View {
    let delay: Double
    @State private var bouncing = false

    var body: some View {
        Circle()
            .fill(AppwinTokens.textLow)
            .frame(width: 6, height: 6)
            .offset(y: bouncing ? -3 : 0)
            .animation(
                .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: bouncing
            )
            .onAppear { bouncing = true }
    }
}
