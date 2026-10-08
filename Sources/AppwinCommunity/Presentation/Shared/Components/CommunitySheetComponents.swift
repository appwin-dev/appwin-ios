import SwiftUI

// Building blocks of the Figma « Appwin InApp » sheets (report, moderation,
// sanctions): the header action, the info box, form fields and check lists.

/// Figma header action (« Valider », « Supprimer », « Épingler »…): 12pt semibold
/// on a rounded 12 fill. `brand` follows the studio's theme; the others are the
/// fixed moderation colours.
struct CommunityActionPill: View {
    enum Tone { case brand, caution, alert, invert }

    let title: String
    var tone: Tone = .brand
    var icon: CommunityIcon?
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(foreground)
                } else if let icon {
                    CommunityIconView(icon: icon, size: 12, color: foreground)
                }
                Text(title)
                    .font(theme.font(12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled && !isLoading ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }

    private var foreground: Color {
        tone == .brand ? theme.colors.onAccent : .white
    }

    private var background: AnyShapeStyle {
        switch tone {
        case .brand: return theme.composeFill
        case .caution: return AnyShapeStyle(AppwinCommunityPalette.caution)
        case .alert: return AnyShapeStyle(AppwinCommunityPalette.alert)
        case .invert: return AnyShapeStyle(AppwinCommunityPalette.invert)
        }
    }
}

/// Text with `**bold**` spans, as the Figma info boxes write « @name » or « modérateur ».
struct CommunityMarkdownText: View {
    let markdown: String
    var size: CGFloat = 12
    var color: Color?

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Text(attributed)
            .font(theme.font(size))
            .foregroundStyle(color ?? theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var text = (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].font = theme.font(size, weight: .semibold)
        }
        return text
    }
}

/// Figma « info »: bg/low, an info circle, 12pt secondary text.
struct CommunityInfoBox: View {
    let markdown: String

    @Environment(\.communityTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            CommunityIconView(icon: .infoCircle, size: 16, color: theme.colors.textSecondary)
            CommunityMarkdownText(markdown: markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(theme.colors.raised, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Figma « input/text-area »: a label and its counter over a 120pt white field.
struct CommunityTextArea: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var limit = 1000

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(theme.font(14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer(minLength: 0)
                Text(CommunityStrings.characterCounter(text.count, limit))
                    .font(theme.font(10, weight: .bold))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(theme.font(14))
                        .foregroundStyle(theme.colors.textTertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text, axis: .vertical)
                    .font(theme.font(14))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(4...8)
                    .onChange(of: text) { value in
                        if value.count > limit { text = String(value.prefix(limit)) }
                    }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.raised, lineWidth: 1))
        }
    }
}

/// Figma « select »: a 40pt white field with the chosen option and a chevron.
struct CommunitySelectField<Option: Hashable>: View {
    let label: String
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(theme.font(14, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(title(option)).tag(option)
                    }
                }
            } label: {
                HStack {
                    Text(title(selection))
                        .font(theme.font(12, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer(minLength: 0)
                    CommunityIconView(icon: .altArrowDown, size: 12, color: theme.colors.textTertiary)
                }
                .padding(12)
                .frame(height: 40)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.raised, lineWidth: 1))
            }
        }
    }
}

/// Figma single-choice list (report and motif sheets): a white card, ruled
/// rows, a check on the chosen one.
struct CommunityCheckList<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option?
    let title: (Option) -> String

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                if index > 0 {
                    Rectangle().fill(theme.colors.raised).frame(height: 1).padding(.vertical, 8)
                }
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 8) {
                        Text(title(option))
                            .font(theme.font(14, weight: .medium))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        if selection == option {
                            CommunityIconView(icon: .check, size: 16, color: theme.colors.textPrimary)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Figma « sanction » on a moderated post: « Supprimé » in red, « Masqué » in amber.
struct CommunitySanctionBadge: View {
    enum Kind { case hidden, removed }

    let kind: Kind

    @Environment(\.communityTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            CommunityIconView(icon: kind == .removed ? .forbidden : .ghost, size: 10, color: tint)
            Text(kind == .removed ? CommunityStrings.statusRemoved : CommunityStrings.statusHidden)
                .font(theme.font(10, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            kind == .removed ? AppwinCommunityPalette.alertSoft : AppwinCommunityPalette.cautionSoft,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var tint: Color {
        kind == .removed ? AppwinCommunityPalette.alert : AppwinCommunityPalette.caution
    }
}

/// Figma « badge admin »: an indigo disc with a white shield star, at the bottom
/// right of an author's avatar.
struct CommunityAdminBadge: View {
    /// Of the avatar it sits on: 16pt on a 40pt avatar.
    let avatarSize: CGFloat

    var body: some View {
        let size = max(10, avatarSize * 0.4)
        CommunityIconView(icon: .shieldStar, size: size * 0.625, color: .white)
            .frame(width: size, height: size)
            .background(AppwinCommunityPalette.adminBadge, in: Circle())
    }
}

/// Figma « badge/number-s »: the red counter on the flag and the bell.
struct CommunityCountBadge: View {
    let count: Int

    @Environment(\.communityTheme) private var theme

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(theme.font(10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(AppwinCommunityPalette.alert, in: Capsule())
    }
}

/// Figma « Appwin InApp » sheet: « Annuler » / title / action pill over bg/page,
/// the content scrolling under it.
struct CommunitySheetScaffold<Trailing: View, Content: View>: View {
    let title: String
    var leadingTitle = CommunityStrings.cancel
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            CommunityNavHeader(
                leadingTitle: leadingTitle,
                onLeading: { dismiss() },
                title: title,
                verticalPadding: 20,
                trailing: trailing
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
    }
}

/// The member a sanction sheet is about: their avatar and name, centred.
struct CommunityMemberHeader: View {
    let nickname: String
    let avatarUrl: URL?

    @Environment(\.communityTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            CommunityAvatar(url: avatarUrl, nickname: nickname, size: 40)
            Text(nickname)
                .font(theme.font(14, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A failed sheet action, under its form: the sheet stays open to retry.
struct CommunityErrorLine: View {
    @Environment(\.communityTheme) private var theme

    var body: some View {
        Text(CommunityStrings.actionFailed)
            .font(theme.font(12, weight: .medium))
            .foregroundStyle(AppwinCommunityPalette.alert)
    }
}
