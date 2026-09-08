//
//  FaqList.swift
//  AppwinSupport
//
//  Home FAQ section, 1:1 with `faq-preview.tsx`: category cards plus articles.
//

import SwiftUI

struct FaqList: View {
  let groups: [FaqGroup]
  @Environment(\.appwinTheme) private var theme

  private let cardBorder = Color(hex: 0xF1F5F9)

  var body: some View {
    if !groups.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(groups) { group in
          FaqCategoryCard(group: group, cardBorder: cardBorder)
        }
      }
    }
  }
}

private struct FaqCategoryCard: View {
  let group: FaqGroup
  let cardBorder: Color
  @Environment(\.appwinTheme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text(group.category.name)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(theme.colors.textPrimary)
          .lineLimit(1)

        Spacer(minLength: 0)

        FaqCountBadge(count: group.articles.count)

        SolarIcon(kind: .altArrowRight, color: theme.colors.textPrimary, size: 12)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      if !group.articles.isEmpty {
        Rectangle()
          .fill(cardBorder)
          .frame(height: 1)

        ForEach(Array(group.articles.prefix(4).enumerated()), id: \.element.id) { index, article in
          NavigationLink(value: AppwinRoute.faq(article)) {
            HStack(spacing: 8) {
              Text(article.question)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(hex: 0x334156))
                .lineLimit(1)
                .multilineTextAlignment(.leading)

              Spacer(minLength: 0)

              SolarIcon(kind: .altArrowRight, color: Color(hex: 0x94A3B8), size: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          if index < min(group.articles.count, 4) - 1 {
            Rectangle()
              .fill(cardBorder)
              .frame(height: 1)
          }
        }

        if group.articles.count > 4 {
          Text("+\(group.articles.count - 4) autre\(group.articles.count - 4 > 1 ? "s" : "")")
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(Color(hex: 0x94A3B8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        Rectangle()
          .fill(cardBorder)
          .frame(height: 1)
        Text("Aucun article")
          .font(.system(size: 11, weight: .regular))
          .foregroundColor(Color(hex: 0x94A3B8))
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        .strokeBorder(cardBorder, lineWidth: 1)
    )
  }
}

/// Badge compteur orange - Figma badge/number-default (`decorative-orange`).
private struct FaqCountBadge: View {
  let count: Int

  var body: some View {
    Text("\(count)")
      .font(.system(size: 10, weight: .semibold))
      .foregroundColor(Color(hex: 0xEA580B))
      .padding(.horizontal, 6)
      .frame(minWidth: 16, minHeight: 16)
      .background(Color(hex: 0xFFEDD5))
      .clipShape(Capsule())
  }
}
