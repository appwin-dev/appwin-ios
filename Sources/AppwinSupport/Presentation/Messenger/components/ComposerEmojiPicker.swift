import SwiftUI

/// Compact emoji grid for the messenger composer (dashboard SmileCircle parity).
struct ComposerEmojiPicker: View {
  let onPick: (String) -> Void

  private static let emojis: [String] = [
    "😀", "😃", "😄", "😁", "😅", "😂", "🤣", "😊",
    "😇", "🙂", "😉", "😍", "🥰", "😘", "😗", "😋",
    "😜", "🤪", "🤨", "🧐", "😎", "🤩", "🥳", "😏",
    "😒", "😞", "😔", "😟", "😕", "🙁", "😣", "😖",
    "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡",
    "🤬", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰",
    "😥", "😓", "🤗", "🤔", "🤭", "🤫", "🤥", "😶",
    "👍", "👎", "👏", "🙌", "🤝", "🙏", "💪", "✌️",
    "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💔",
    "🔥", "✨", "⭐", "💯", "✅", "❌", "🎉", "🎊",
  ]

  var body: some View {
    ScrollView {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
        spacing: 4
      ) {
        ForEach(Self.emojis, id: \.self) { emoji in
          Button {
            onPick(emoji)
          } label: {
            Text(emoji)
              .font(.system(size: 22))
              .frame(maxWidth: .infinity)
              .frame(height: 36)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(12)
    }
    .frame(width: 300, height: 280)
  }
}
