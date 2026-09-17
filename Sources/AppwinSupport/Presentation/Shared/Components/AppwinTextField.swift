//
//  AppwinTextField.swift
//  AppwinSupport
//
//  Champ de saisie « pilule » du design system (composer du chat, recherche…).
//  Multiline: grows to five lines then scrolls.
//
//      AppwinTextField("Ask a question", text: $messageBody)
//
//  For a full composer (field plus send button), compose with AppwinIconButton.
//

import SwiftUI

struct AppwinTextField: View {
    let placeholder: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 1...5

    /// `AppwinTextField("Placeholder", text: $x)`: placeholder first, no label.
    init(_ placeholder: String, text: Binding<String>, lineLimit: ClosedRange<Int> = 1...5) {
        self.placeholder = placeholder
        self._text = text
        self.lineLimit = lineLimit
    }

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(AppwinTypography.font(.bodyM))
            .foregroundColor(AppwinTokens.textHigh)
            .tint(AppwinTokens.accent)
            .lineLimit(lineLimit)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(AppwinTokens.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppwinTokens.border, lineWidth: 1)
            )
    }
}

// MARK: - Preview

private struct AppwinTextFieldPreview: View {
    @State private var text = ""
    var body: some View {
        HStack(spacing: 8) {
            AppwinTextField("Posez une question", text: $text)
            AppwinIconButton(.plain2, style: .filled) {}
        }
        .padding()
        .background(AppwinTokens.surface)
    }
}

#Preview {
    AppwinTextFieldPreview()
}
