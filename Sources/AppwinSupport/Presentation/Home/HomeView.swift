// Home screen, laid out 1:1 with the dashboard FaqPreview.

import SwiftUI
import AppwinCore

struct HomeView: View {
  /// When nil, the host app owns the way out (embedded tab). When set, closes
  /// the modal opened by `presentMessenger`.
  var onClose: (() -> Void)? = nil

  @Environment(\.appwinTheme) private var theme

  @EnvironmentObject private var session: AppwinSession
  @EnvironmentObject private var conversationStore: ConversationStore
  @EnvironmentObject private var faqStore: FaqStore
  @EnvironmentObject private var configStore: ConfigStore
  @StateObject private var router = AppwinRouter()

  private var config: MessengerConfig { configStore.config }

  /// Preview background, slate-100.
  private let screenBg = Color(hex: 0xF1F5F9)

  /// Customer-record creation failure, if there was one.
  @State private var bootstrapError: Error?

  var body: some View {
    NavigationStack(path: $router.path) {
      Group {
        if session.customer != nil {
          content
        } else if let bootstrapError {
          // A real message: "session not initialised" said neither what was
          // missing nor what to do about it.
          failure(bootstrapError)
        } else {
          ProgressView()
            .task { await bootstrapCustomer() }
        }
      }
      .navigationDestination(for: AppwinRoute.self) { $0.destination }
    }
    .environmentObject(router)
    // Opened from an in-app banner or a push tap: go to the thread rather than
    // leaving the reader to find it. Consumed once, so a later manual open
    // still lands on home.
    .task {
      guard let id = AppwinSupport.pendingConversationId else { return }
      AppwinSupport.pendingConversationId = nil
      await conversationStore.get(conversationId: id)
      guard let conversation = conversationStore.conversation else { return }
      router.push(.messenger(conversation))
    }
  }

  /// Creates the customer record if the host app has not.
  ///
  /// So the messenger opens after `AppwinCore.configure` alone, like the
  /// community feed: the host app does not need to know an identity call to
  /// show a screen.
  private func bootstrapCustomer() async {
    do {
      session.setCustomer(try await AppwinSupport.ensureCustomer())
      bootstrapError = nil
    } catch {
      bootstrapError = error
    }
  }

  private func failure(_ error: Error) -> some View {
    VStack(spacing: 12) {
      Text("Le messenger n'a pas pu s'ouvrir")
        .font(AppwinTypography.font(.headline))
        .foregroundColor(theme.colors.textPrimary)
      Text("\(error)")
        .font(AppwinTypography.font(.caption))
        .multilineTextAlignment(.center)
        .foregroundColor(theme.colors.textSecondary)
      Button("Réessayer") {
        bootstrapError = nil
      }
      .font(AppwinTypography.font(.bodyS))
      .foregroundColor(theme.colors.accent)
    }
    .padding(24)
  }

  private var content: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Header(context: config.context, onClose: onClose)

          if config.design.bannerSource != .none {
            MessengerBannerView(
              design: config.design,
              accent: theme.colors.accent,
              accentHex: theme.accentHex
            )
          }

          greeting

          VStack(spacing: 12) {
            NavigationLink(value: AppwinRoute.newConversation) {
              StartConversationCard()
            }
            .buttonStyle(.plain)

            NavigationLink(value: AppwinRoute.conversations) {
              ConversationsCard()
            }
            .buttonStyle(.plain)
          }

          if config.modules.faqEnabled {
            FaqList(groups: faqStore.groups)
          }
        }
        .padding(20)
      }
    }
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: theme.radius.sheet,
        topTrailingRadius: theme.radius.sheet
      )
    )
    .background(screenBg)
    .task {
      if config.modules.faqEnabled {
        await faqStore.load()
      }
    }
  }

  private var greeting: some View {
    let firstName = session.customer?.name?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: " ")
      .first
      .map(String.init) ?? "toi"

    return VStack(alignment: .leading, spacing: 0) {
      Text("Hello \(firstName) 👋")
      Text("Besoin d'aide ?")
    }
    .font(.system(size: 22, weight: .medium))
    .foregroundColor(theme.colors.textPrimary)
    .lineSpacing(0)
  }
}
