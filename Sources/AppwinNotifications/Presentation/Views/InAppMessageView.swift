import SwiftUI

struct InAppMessageView: View {
  let message: InAppMessage
  let onAction: (InAppMessageAction) -> Void

  var body: some View {
    switch message.format {
    case .banner:
      bannerLayout
    case .fullscreen:
      fullscreenLayout
    case .imageOnly:
      imageOnlyLayout
    case .modal:
      modalLayout
    }
  }

  private var modalLayout: some View {
    ZStack {
      Color.black.opacity(0.45)
        .ignoresSafeArea()
        .onTapGesture { onAction(.dismiss) }
      VStack(spacing: 16) {
        contentBody
        buttonRow
      }
      .padding(20)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      .padding(.horizontal, 24)
    }
  }

  private var bannerLayout: some View {
    VStack {
      HStack(alignment: .top, spacing: 12) {
        contentBody
        Button {
          onAction(.dismiss)
        } label: {
          Image(systemName: "xmark")
            .foregroundStyle(.secondary)
        }
      }
      .padding(16)
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .onTapGesture { onAction(.primaryTap) }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.clear)
  }

  private var fullscreenLayout: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 20) {
        Spacer()
        contentBody
        buttonRow
        Spacer()
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(.systemBackground))

      Button {
        onAction(.dismiss)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .symbolRenderingMode(.hierarchical)
      }
      .padding(20)
    }
  }

  private var imageOnlyLayout: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let imageUrl = message.content.imageUrl, let url = URL(string: imageUrl) {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
              .onTapGesture { onAction(.primaryTap) }
          default:
            ProgressView()
          }
        }
      }
      VStack {
        HStack {
          Spacer()
          Button {
            onAction(.dismiss)
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title2)
              .foregroundStyle(.white)
          }
        }
        .padding()
        Spacer()
      }
    }
  }

  @ViewBuilder
  private var contentBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let imageUrl = message.content.imageUrl, message.format != .imageOnly,
         let url = URL(string: imageUrl) {
        AsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill().frame(maxHeight: 180).clipped()
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      if let title = message.content.title {
        Text(title).font(.headline)
      }
      if let body = message.content.body {
        Text(body).font(.body).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var buttonRow: some View {
    if let buttons = message.content.buttons, !buttons.isEmpty {
      VStack(spacing: 8) {
        ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
          Button(button.label) {
            onAction(.button(index: index, button: button))
          }
          .buttonStyle(.borderedProminent)
          .frame(maxWidth: .infinity)
        }
      }
    } else if message.content.deeplink != nil {
      Button(NotificationsStrings.ctaOpen) {
        onAction(.primaryTap)
      }
      .buttonStyle(.borderedProminent)
      .frame(maxWidth: .infinity)
    }
  }
}
