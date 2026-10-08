// The Solar icons of the Figma InApp frames, shipped as vector template
// images in `CommunityIcons.xcassets`: SF Symbols read as a different product
// next to the Support SDK and the dashboard, which both use Solar.

import SwiftUI

enum CommunityIcon: String {
    case heart = "solar_heart"
    case heartFill = "solar_heart_fill"
    case chatLine = "solar_chat_line"
    case chatLineDuotone = "solar_chat_line_duotone"
    case gallery = "solar_gallery"
    case videocamera = "solar_videocamera"
    case chart = "solar_chart"
    case chartBold = "solar_chart_bold"
    case plain = "solar_plain"
    case penNewSquare = "solar_pen_new_square"
    case arrowUp = "solar_arrow_up"
    case pin = "solar_pin"
}

struct CommunityIconView: View {
    let icon: CommunityIcon
    var size: CGFloat = 20
    var color: Color

    var body: some View {
        Image(icon.rawValue, bundle: CommunityStrings.resourceBundle)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(color)
            .accessibilityHidden(true)
    }
}
