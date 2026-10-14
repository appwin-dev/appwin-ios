import SwiftUI

/// Figma « Régler l'épinglage » (178:3968): an end date, a view cap per member,
/// or both; the pin lifts at the first one reached.
struct PinSettingsSheet: View {
    let onPin: (PinSettings) async throws -> Void

    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var usesDate = true
    @State private var until = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var usesViews = false
    @State private var views = 2
    @State private var isSending = false
    @State private var failed = false

    var body: some View {
        CommunitySheetScaffold(title: CommunityStrings.pinTitle) {
            CommunityActionPill(
                title: CommunityStrings.pinAction,
                isEnabled: usesDate || usesViews,
                isLoading: isSending,
                action: pin
            )
        } content: {
            CommunityInfoBox(markdown: CommunityStrings.pinInfo)
            card(
                title: CommunityStrings.pinUntilTitle,
                hint: CommunityStrings.pinUntilHint,
                isOn: $usesDate
            ) {
                DatePicker("", selection: $until, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
            card(
                title: CommunityStrings.pinViewsTitle,
                hint: CommunityStrings.pinViewsHint,
                isOn: $usesViews
            ) {
                HStack(spacing: 8) {
                    TextField("", value: $views, format: .number)
                        .keyboardType(.numberPad)
                        .font(theme.font(14))
                        .foregroundStyle(theme.colors.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(width: 74, height: 40)
                        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.border, lineWidth: 1))
                    Text(CommunityStrings.pinTimes)
                        .font(theme.font(14))
                        .foregroundStyle(theme.colors.textPrimary)
                }
            }
            if failed { CommunityErrorLine() }
        }
    }

    private func card<Body: View>(
        title: String,
        hint: String,
        isOn: Binding<Bool>,
        @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(theme.font(14, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(hint)
                        .font(theme.font(12))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(theme.colors.accent)
            }
            if isOn.wrappedValue { body() }
        }
        .padding(16)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.raised, lineWidth: 1))
    }

    private func pin() {
        isSending = true
        failed = false
        let settings = PinSettings(
            until: usesDate ? Calendar.current.startOfDay(for: until).addingTimeInterval(86_399) : nil,
            maxViewsPerMember: usesViews ? max(1, views) : nil
        )
        Task {
            do {
                try await onPin(settings)
                dismiss()
            } catch {
                failed = true
            }
            isSending = false
        }
    }
}
