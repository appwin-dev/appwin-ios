//
//  FileBubble.swift
//  AppwinSupport
//
//  File attachment (PDF, doc), mirroring the horizontal SaaS `Attachment`: a
//  doc icon in a muted square, the name, and an external link. Tapping opens a
//  freshly signed URL in the browser through `openFresh`.
//

import SwiftUI

struct FileBubble: View {
    let attachment: Attachment

    @EnvironmentObject private var messageStore: MessageStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Task { await openFresh(attachment, store: messageStore, openURL) }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppwinTokens.surfaceMuted)
                        .frame(width: 32, height: 32)
                    SolarIcon(kind: .document, color: AppwinTokens.textHigh, size: 16)
                }

                Text(attachment.filename)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppwinTokens.textHigh)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppwinTokens.textLow)
            }
            .padding(6)
            .padding(.trailing, 4)
            .frame(minWidth: 200, maxWidth: 280, alignment: .leading)
            .background(AppwinTokens.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppwinTokens.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: SupportStrings.openFile, attachment.filename))
    }
}
