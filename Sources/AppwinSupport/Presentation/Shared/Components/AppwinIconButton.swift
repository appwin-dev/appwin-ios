//
//  AppwinIconButton.swift
//  AppwinSupport
//
//  Circular icon button (back, close). Solar Linear, not SF Symbols.

import SwiftUI

struct AppwinIconButton: View {
    let kind: SolarIcon.Kind
    var style: Style = .plain
    var size: CGFloat = 40
    let action: () -> Void

    enum Style {
        case plain
        case onAccent
        case filled
    }

    init(_ kind: SolarIcon.Kind, style: Style = .plain, size: CGFloat = 40, action: @escaping () -> Void) {
        self.kind = kind
        self.style = style
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SolarIcon(kind: kind, color: foreground, size: size * 0.4)
                .frame(width: size, height: size)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .plain:    return AppwinTokens.iconHigh
        case .onAccent: return AppwinTokens.iconOnBrand
        case .filled:   return AppwinTokens.iconOnBrand
        }
    }

    private var background: Color {
        switch style {
        case .plain:    return AppwinPalette.grey100
        case .onAccent: return AppwinPalette.onBrand.opacity(0.2)
        case .filled:   return AppwinTokens.accent
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AppwinIconButton(.altArrowRight) {}
        AppwinIconButton(.close, style: .onAccent) {}
        AppwinIconButton(.plain2, style: .filled) {}
    }
    .padding(40)
    .background(AppwinTokens.accent)
}
