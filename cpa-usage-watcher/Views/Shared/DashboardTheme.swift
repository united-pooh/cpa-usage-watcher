import SwiftUI

enum DashboardTheme {
    static let cream = Color(red: 253.0 / 255.0, green: 251.0 / 255.0, blue: 248.0 / 255.0)
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.902)
    static let paperDeep = Color(red: 0.937, green: 0.910, blue: 0.843)
    static let panel = Color(red: 0.995, green: 0.989, blue: 0.973)
    static let panelRaised = Color(red: 1.0, green: 0.996, blue: 0.984)
    static let sidebar = Color(red: 0.968, green: 0.946, blue: 0.902)
    static let toolbar = cream
    static let ink = Color(red: 0.165, green: 0.149, blue: 0.125)
    static let mutedInk = Color(red: 0.435, green: 0.396, blue: 0.341)
    static let softInk = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.42)
    static let hairline = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.13)
    static let strongHairline = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.20)
    static let shadow = Color(red: 0.245, green: 0.157, blue: 0.059).opacity(0.10)

    static let orange = Color(red: 1.0, green: 0.478, blue: 0.271)
    static let orangeDeep = Color(red: 0.910, green: 0.373, blue: 0.165)
    static let orangeSoft = Color(red: 1.0, green: 0.851, blue: 0.780)
    static let blue = Color(red: 0.271, green: 0.718, blue: 1.0)
    static let blueDeep = Color(red: 0.122, green: 0.561, blue: 0.851)
    static let blueSoft = Color(red: 0.784, green: 0.910, blue: 0.984)
    static let yellow = Color(red: 1.0, green: 0.824, blue: 0.271)
    static let yellowSoft = Color(red: 1.0, green: 0.937, blue: 0.722)
    static let green = Color(red: 0.180, green: 0.651, blue: 0.416)
    static let red = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let purple = Color(red: 0.486, green: 0.337, blue: 0.855)

    static let cornerRadius: CGFloat = 18
    static let compactRadius: CGFloat = 8
    static let cardRadius: CGFloat = 22

    static func accent(_ index: Int) -> Color {
        [orange, blue, yellow, green][abs(index) % 4]
    }
}

struct DashboardChromeButtonStyle: ButtonStyle {
    var accent: Color = DashboardTheme.blue
    var isProminent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? (isProminent ? DashboardTheme.cream : DashboardTheme.ink) : DashboardTheme.mutedInk.opacity(0.58))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                    .fill(isProminent ? accent : (isEnabled && configuration.isPressed ? accent.opacity(0.18) : DashboardTheme.panelRaised))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                    .stroke(isProminent ? accent : (isEnabled && configuration.isPressed ? accent.opacity(0.55) : DashboardTheme.hairline), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.58)
    }
}

struct DashboardIconButtonStyle: ButtonStyle {
    var accent: Color = DashboardTheme.blue
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(!isEnabled ? DashboardTheme.mutedInk.opacity(0.58) : configuration.isPressed ? accent : DashboardTheme.ink)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                    .fill(isEnabled && configuration.isPressed ? accent.opacity(0.18) : DashboardTheme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                    .stroke(isEnabled && configuration.isPressed ? accent.opacity(0.55) : DashboardTheme.hairline, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.58)
    }
}
