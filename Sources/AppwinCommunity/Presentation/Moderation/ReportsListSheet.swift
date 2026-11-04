import SwiftUI

/// Figma « N signalements » (178:3145): why members reported a content.
struct ReportsListSheet: View {
    let reports: [ModerationReport]
    /// Hidden by the report threshold rather than by a moderator.
    let wasAutoHidden: Bool

    @Environment(\.communityTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        CommunitySheetScaffold(
            title: CommunityStrings.reportsCount(reports.count),
            leadingTitle: CommunityStrings.back
        ) {
            EmptyView()
        } content: {
            if wasAutoHidden {
                CommunityInfoBox(markdown: CommunityStrings.reportsAutoHidden(reports.count))
            }
            VStack(spacing: 0) {
                ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                    if index > 0 {
                        Rectangle().fill(theme.colors.raised).frame(height: 1)
                    }
                    row(report)
                }
            }
        }
    }

    private func row(_ report: ModerationReport) -> some View {
        HStack(alignment: .center, spacing: 8) {
            CommunityIconView(icon: .flag, size: 16, color: AppwinCommunityPalette.caution)
            Text(CommunityStrings.reasonLabel(report.reason))
                .font(theme.font(14, weight: .medium))
                .foregroundStyle(AppwinCommunityPalette.caution)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(report.createdAt.formatted(
                .dateTime.day().month(.abbreviated).hour().minute().locale(locale)
            ))
            .font(theme.font(12))
            .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.vertical, 16)
    }
}
