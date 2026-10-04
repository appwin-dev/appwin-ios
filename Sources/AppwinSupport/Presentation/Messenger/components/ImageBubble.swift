//
//  ImageBubble.swift
//  AppwinSupport
//
//  Inline image attachment, iMessage style. It goes through `AttachmentImage`
//  and its shared memory cache: once loaded for the thumbnail it is reused
//  as-is full screen, so tapping costs no download. The cache also handles
//  re-signing when the URL has expired.
//

import SwiftUI

struct ImageBubble: View {
    let attachment: Attachment

    @EnvironmentObject private var messageStore: MessageStore
    @State private var isPresentingViewer = false

    var body: some View {
        AttachmentImage(attachment: attachment) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ProgressView()
        }
        .frame(width: 240, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { isPresentingViewer = true }
        .fullScreenCover(isPresented: $isPresentingViewer) {
            ImageViewerView(attachment: attachment)
                .environmentObject(messageStore)
        }
    }
}
