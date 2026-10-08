//
//  FaqDetailView.swift
//  AppwinSupport
//
//  FAQ article - Figma support-convo 40:7405: the question in a brand-soft
//  pill (the studio's colour at 24%), then the markdown answer.
//

import SwiftUI

struct FaqDetailView: View {
  let faq: Faq
  @Environment(\.appwinTheme) private var theme
  @EnvironmentObject private var router: AppwinRouter
  @EnvironmentObject private var faqStore: FaqStore

  /// "FAQ Générale": the section name followed by the article's category.
  private var title: String {
    guard let category = faqStore.groups.first(where: { $0.category.id == faq.categoryId })?.category
    else { return SupportStrings.faq }
    return "\(SupportStrings.faq) \(category.name)"
  }

  var body: some View {
    VStack(spacing: 0) {
      AppwinNavBar(title: title) { router.pop() }

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(faq.question)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(theme.colors.textPrimary)
            .appwinCard(cornerRadius: theme.radius.card, fill: theme.colors.accent.opacity(0.24))

          MarkdownText(
            faq.answer,
            color: theme.colors.textSecondary,
            bodyFont: .system(size: 15, weight: .regular)
          )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(theme.colors.page)
    .navigationBarHidden(true)
    .enableInteractivePopGesture()
  }
}
