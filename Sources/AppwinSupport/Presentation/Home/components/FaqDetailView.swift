//
//  FaqDetailView.swift
//  AppwinSupport
//
//  FAQ article: the markdown answer, after a tap from home.
//

import SwiftUI

struct FaqDetailView: View {
  let faq: Faq
  @Environment(\.appwinTheme) private var theme
  @EnvironmentObject private var router: AppwinRouter
  @EnvironmentObject private var configStore: ConfigStore

  private var title: String {
    let agent = configStore.config.context.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !agent.isEmpty { return agent }
    return configStore.config.context.projectName
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          router.pop()
        } label: {
          SolarIcon(kind: .altArrowLeft, color: theme.colors.textPrimary, size: 20)
        }
        .accessibilityLabel(SupportStrings.back)

        Spacer(minLength: 0)

        Text(title)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(theme.colors.textPrimary)

        Spacer(minLength: 0)

        Color.clear.frame(width: 20, height: 20)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(faq.question)
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(theme.colors.textPrimary)

          MarkdownText(faq.answer, color: theme.colors.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(Color(hex: 0xF1F5F9))
    .navigationBarHidden(true)
  }
}
