import SwiftUI

/// Writing a post.
///
/// The character counter appears when approaching the project's limit, not from
/// the first word: showing "3 / 1500" informs nobody and makes the constraint
/// feel tighter than it is.
struct ComposerView: View {
    @EnvironmentObject private var session: CommunitySession
    @Environment(\.communityTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let onPublished: (CommunityPost) -> Void

    @State private var body_ = ""
    @State private var groupId: String?
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var limit: Int { session.config.limits.postMaxLength }
    private var remaining: Int { limit - body_.count }
    /// Counter threshold: the last fifth of the limit.
    private var showsCounter: Bool { remaining <= limit / 5 }
    private var canSubmit: Bool {
        !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remaining >= 0
            && !isSending
    }

    /// Groups the member is allowed to post in.
    private var postableGroups: [CommunityGroup] {
        session.groups.filter(\.canPost)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                if postableGroups.count > 1 {
                    groupPicker
                }

                TextEditor(text: $body_)
                    .focused($isFocused)
                    .font(theme.font(16))
                    .foregroundStyle(theme.colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text(CommunityStrings.composerPlaceholder)
                                .font(theme.font(16))
                                .foregroundStyle(theme.colors.textTertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(theme.font(13))
                        .foregroundStyle(theme.colors.danger)
                }

                HStack {
                    Spacer()
                    if showsCounter {
                        Text("\(remaining)")
                            .font(theme.font(13, weight: .medium))
                            .foregroundStyle(
                                remaining < 0 ? theme.colors.danger : theme.colors.textTertiary
                            )
                    }
                }
            }
            .padding(theme.spacing.lg)
            .background(theme.colors.background)
            .navigationTitle(CommunityStrings.newPost)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(CommunityStrings.cancel) { dismiss() }
                        .foregroundStyle(theme.colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CommunityStrings.publish, action: submit)
                        .font(theme.font(15, weight: .semibold))
                        .foregroundStyle(canSubmit ? theme.colors.accent : theme.colors.textTertiary)
                        .disabled(!canSubmit)
                }
            }
            .onAppear {
                groupId = session.selectedGroupId ?? postableGroups.first?.id
                isFocused = true
            }
        }
    }

    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.sm) {
                ForEach(postableGroups) { group in
                    Button {
                        groupId = group.id
                    } label: {
                        Text([group.emoji, group.name].compactMap { $0 }.joined(separator: " "))
                            .font(theme.font(13, weight: groupId == group.id ? .semibold : .medium))
                            .foregroundStyle(
                                groupId == group.id
                                    ? theme.colors.onAccent
                                    : theme.colors.textSecondary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                if groupId == group.id {
                                    Capsule().fill(theme.accentFill)
                                } else {
                                    Capsule().fill(theme.colors.surface)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSending = true
        errorMessage = nil

        Task {
            do {
                let post = try await Factory.repository().createPost(
                    groupId: groupId,
                    body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
                    media: []
                )
                onPublished(post)
                dismiss()
            } catch {
                // The server carries the refusals that matter (anti-flood,
                // moderation), so its message beats a generic one.
                errorMessage = String(describing: error)
            }
            isSending = false
        }
    }
}
