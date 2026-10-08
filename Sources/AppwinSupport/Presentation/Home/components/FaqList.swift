//
//  FaqList.swift
//  AppwinSupport
//
//  Home FAQ section - Figma support-home 40:7225: a "FAQ" heading, then per
//  category a light label over one card per article.
//

import SwiftUI

struct FaqList: View {
  let groups: [FaqGroup]
  @Environment(\.appwinTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text(SupportStrings.faq)
        .font(.system(size: 24, weight: .medium))
        .foregroundColor(theme.colors.textPrimary)

      ForEach(groups) { group in
        VStack(alignment: .leading, spacing: 4) {
          Text(group.category.name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AppwinTokens.textLow)

          if group.articles.isEmpty {
            Text(SupportStrings.noArticles)
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(AppwinTokens.textLow)
          }

          ForEach(group.articles) { article in
            NavigationLink(value: AppwinRoute.faq(article)) {
              HStack(spacing: 8) {
                Text(article.question)
                  .font(.system(size: 14, weight: .medium))
                  .foregroundColor(theme.colors.textPrimary)
                  .multilineTextAlignment(.leading)
                  // A button label clamps to one line otherwise; Figma wraps.
                  .fixedSize(horizontal: false, vertical: true)
                  .frame(maxWidth: .infinity, alignment: .leading)

                SolarIcon(kind: .altArrowRight, color: AppwinTokens.iconLow, size: 16)
              }
              .appwinCard(cornerRadius: theme.radius.card)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}
