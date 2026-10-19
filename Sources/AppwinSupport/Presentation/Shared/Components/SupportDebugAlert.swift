#if DEBUG
import SwiftUI
import AppwinCore

/// What the debug alert says about a verdict. Developer-facing, so plain English
/// literals: an end user never sees it.
struct SupportDebugDiagnosis: Equatable {
    let code: String
    let message: String
    let actionTitle: String
    let actionUrl: URL

    private static let dashboard = URL(string: "https://dashboard.appwin.io")!
    private static let pricing = URL(string: "https://appwin.io/pricing")!
    private static let docs = URL(string: "https://appwin.io/docs/products/support")!

    /// Support open only because this is a debug build.
    static let debugUnlocked = SupportDebugDiagnosis(
        code: "ready (debug only)",
        message: "Unlocked for this debug build only. Your plan does not include "
            + "Support: release builds will refuse to open the messenger.",
        actionTitle: "See plans",
        actionUrl: pricing
    )

    /// `nil` for a ready verdict: there is nothing to explain.
    init?(result: AppwinInitResult?) {
        switch result {
        case .ready:
            return nil
        case .unavailable(.plan):
            self.init(
                code: "unavailable(plan)",
                message: "Your plan does not include Support. Upgrade it to open the "
                    + "messenger in release builds.",
                actionTitle: "See plans",
                actionUrl: Self.pricing
            )
        case .unavailable(.disabled):
            self.init(
                code: "unavailable(disabled)",
                message: "Support is switched off for this project. Turn it on in the "
                    + "dashboard, under SDK: the messenger opens without an app update.",
                actionTitle: "Open dashboard",
                actionUrl: Self.dashboard
            )
        case .notConfigured:
            self.init(
                code: "notConfigured",
                message: "AppwinCore.configure() was not called. Call it at launch, "
                    + "before AppwinSupport.initialize().",
                actionTitle: "Open the docs",
                actionUrl: Self.docs
            )
        case .unknown:
            self.init(
                code: "unknown",
                message: "No answer from the server yet. Check the network and the SDK "
                    + "base URL: the answer is cached after the first success.",
                actionTitle: "Open the docs",
                actionUrl: Self.docs
            )
        case nil:
            self.init(
                code: "notInitialized",
                message: "AppwinSupport.initialize() was not called. Call it after "
                    + "configure(), before presenting the messenger.",
                actionTitle: "Open the docs",
                actionUrl: Self.docs
            )
        }
    }

    private init(code: String, message: String, actionTitle: String, actionUrl: URL) {
        self.code = code
        self.message = message
        self.actionTitle = actionTitle
        self.actionUrl = actionUrl
    }
}

/// The dashboard's `SetupBanner` (Figma `alert-banner/large`, 3518:64770),
/// stacked for phone width: the same alert a studio already reads in the SaaS.
struct SupportDebugAlert: View {
    let diagnosis: SupportDebugDiagnosis

    private static let warningHigh = Color(hex: 0xFCD34D)
    private static let warningSolid = Color(hex: 0xD97706)
    private static let shadow = Color(hex: 0x020617)
    private static let ctaEnd = Color(hex: 0xFA7315)

    var body: some View {
        HStack(spacing: 8) {
            DangerCircleIcon(color: Self.warningSolid)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("DEBUG")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0xB45309))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            AppwinPalette.warning.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    Text(diagnosis.code)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppwinPalette.grey500)
                        .lineLimit(1)
                }
                Text(diagnosis.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.warningSolid)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: diagnosis.actionUrl) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text(diagnosis.actionTitle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x9B3412), Self.ctaEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 2)
                    )
                    .shadow(color: Self.shadow.opacity(0.1), radius: 4, y: 4)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Self.shadow.opacity(0.05), radius: 10, y: 16)
        }
        .padding(.leading, 12)
        .padding([.trailing, .vertical], 2)
        .background(
            LinearGradient(colors: [Self.warningHigh, .white], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Solar `Danger Circle` (Bold), as the dashboard draws it: a disc with the
/// exclamation cut out, on a 20x20 grid.
private struct DangerCircleIcon: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 20
            var glyph = Path(ellipseIn: CGRect(x: 1.667 * s, y: 1.667 * s, width: 16.667 * s, height: 16.667 * s))
            glyph.addRoundedRect(
                in: CGRect(x: 9.375 * s, y: 5.208 * s, width: 1.25 * s, height: 6.25 * s),
                cornerSize: CGSize(width: 0.625 * s, height: 0.625 * s)
            )
            glyph.addEllipse(in: CGRect(x: 9.167 * s, y: 12.5 * s, width: 1.667 * s, height: 1.667 * s))
            context.fill(glyph, with: .color(color), style: FillStyle(eoFill: true))
        }
        .accessibilityHidden(true)
    }
}
/// What replaces the messenger while Support is not ready, in debug builds:
/// the diagnosis, then the line a release build shows the end user, so the
/// integrator sees both sides.
struct SupportUnavailableDebugView: View {
    let diagnosis: SupportDebugDiagnosis
    let releaseMessage: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SupportDebugAlert(diagnosis: diagnosis)
                Text(releaseMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(AppwinPalette.grey500)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(AppwinPalette.grey50.ignoresSafeArea())
    }
}
#endif
