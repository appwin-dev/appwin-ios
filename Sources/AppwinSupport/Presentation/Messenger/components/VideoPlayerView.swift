//
//  VideoPlayerView.swift
//  AppwinSupport
//
//  Full-screen in-app video player (AVKit), presented on tapping a
//  `VideoBubble` rather than redirecting to Safari. The URL is re-signed when
//  it opens, because attachment URLs expire.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let attachment: Attachment

    @EnvironmentObject private var messageStore: MessageStore
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            closeButton
        }
        .task {
            let url = (try? await messageStore.freshAttachmentURL(attachmentId: attachment.id))
                ?? attachment.url
            let avPlayer = AVPlayer(url: url)
            player = avPlayer
            avPlayer.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    SolarIcon(kind: .close, color: .white, size: 16)
                        .padding(12)
                        .background(Color.black.opacity(0.5), in: Circle())
                }
                .padding()
            }
            Spacer()
        }
    }
}
