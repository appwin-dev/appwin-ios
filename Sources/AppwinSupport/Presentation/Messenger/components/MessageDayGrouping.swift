// Day separators, same logic as the dashboard's conversation thread.
// Chronological order (oldest to newest) for ScrollViewReader, so the bottom is
// the most recent.

import Foundation

/// Display metadata for consecutive messages from the same author.
struct MessageGroupMeta: Equatable {
    /// Attached to the previous message: same author, same day.
    let isGroupedWithPrevious: Bool
    /// Last of the block; only this one shows the time, the read receipt and
    /// the avatar.
    let isLastInGroup: Bool
}

enum MessageListItem: Identifiable {
    case day(id: String, label: String)
    case message(Message, groupMeta: MessageGroupMeta)

    var id: String {
        switch self {
        case .day(let id, _): return "day-\(id)"
        case .message(let m, _): return m.id
        }
    }
}

enum MessageDayGrouping {
    /// The `messages` store is most-recent-first. Output is chronological:
    /// day separator, then messages oldest to newest, for a natural scroll.
    static func items(from messages: [Message], calendar: Calendar = .current) -> [MessageListItem] {
        guard !messages.isEmpty else { return [] }

        let chronological = Array(messages.reversed())
        var result: [MessageListItem] = []
        var index = 0

        while index < chronological.count {
            let anchor = chronological[index]
            let dayStart = calendar.startOfDay(for: anchor.createdAt)
            var dayMessages: [Message] = []

            while index < chronological.count,
                  calendar.isDate(chronological[index].createdAt, inSameDayAs: dayStart) {
                dayMessages.append(chronological[index])
                index += 1
            }

            result.append(.day(id: dayKey(dayStart), label: formatDayLabel(dayStart, calendar: calendar)))
            for (index, message) in dayMessages.enumerated() {
                let previous = index > 0 ? dayMessages[index - 1] : nil
                let next = index + 1 < dayMessages.count ? dayMessages[index + 1] : nil
                let sameAuthorAsPrevious = previous?.authorType == message.authorType
                let sameAuthorAsNext = next?.authorType == message.authorType
                let meta = MessageGroupMeta(
                    isGroupedWithPrevious: sameAuthorAsPrevious,
                    isLastInGroup: !sameAuthorAsNext
                )
                result.append(.message(message, groupMeta: meta))
            }
        }

        return result
    }

    static func formatDayLabel(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date).capitalized
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
