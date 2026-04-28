import SwiftUI

struct SidebarTitlebarToggleButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardTheme.mutedInk)
                .frame(width: WindowChromeMetrics.systemControlSize, height: WindowChromeMetrics.systemControlSize)
                .background(
                    RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                        .fill(DashboardTheme.panelRaised.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                        .stroke(DashboardTheme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
