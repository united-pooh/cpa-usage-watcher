import SwiftUI

enum SidebarSelection: Hashable {
    case overview
    case events
    case health
    case apiKeys
    case models
    case prices
    case connection
}

struct AppSidebarView: View {
    let snapshot: UsageSnapshot
    let hasLoadedData: Bool
    let isLoading: Bool
    let lastUpdatedAt: Date?
    let baseURL: String
    let selectedItem: SidebarSelection
    let select: (SidebarSelection) -> Void
    let toggleSidebar: () -> Void

    private let horizontalInset: CGFloat = 14
    private let verticalWindowInset: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarTitlebarControls

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    brand

                    SidebarSection(title: "儀表盤") {
                        SidebarItem(
                            title: "使用統計",
                            systemImage: "chart.bar.xaxis",
                            isActive: selectedItem == .overview,
                            action: { select(.overview) }
                        ) {
                            LiveBadge(text: isLoading ? "SYNC" : "LIVE")
                        }
                        SidebarItem(
                            title: "服務健康",
                            systemImage: "sparkle.magnifyingglass",
                            isActive: selectedItem == .health,
                            action: { select(.health) }
                        )
                    }

                    SidebarSection(title: "數據源") {
                        SidebarItem(
                            title: "模型 / 憑證",
                            systemImage: "tag",
                            isActive: selectedItem == .models,
                            action: { select(.models) }
                        )
                        SidebarItem(
                            title: "請求事件",
                            systemImage: "doc.text",
                            isActive: selectedItem == .events,
                            badge: UsageFormatters.integer(snapshot.events.count),
                            action: { select(.events) }
                        )
                        SidebarItem(
                            title: "API Keys",
                            systemImage: "key",
                            isActive: selectedItem == .apiKeys,
                            badge: UsageFormatters.integer(snapshot.credentials.count),
                            action: { select(.apiKeys) }
                        )
                        SidebarItem(
                            title: "價格設置",
                            systemImage: "yensign",
                            isActive: selectedItem == .prices,
                            action: { select(.prices) }
                        )
                    }

                    SidebarSection(title: "系統") {
                        SidebarItem(
                            title: "連接設置",
                            systemImage: "gearshape",
                            isActive: selectedItem == .connection,
                            action: { select(.connection) }
                        )
                    }
                }
                .padding(.horizontal, horizontalInset)
                .padding(.top, verticalWindowInset)
                .padding(.bottom, 10)
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)

            localServiceCard
                .padding(.horizontal, horizontalInset)
                .padding(.top, 10)
                .padding(.bottom, verticalWindowInset)
                .allowsHitTesting(false)
        }
        .background(DashboardTheme.sidebar.ignoresSafeArea(.container, edges: .top))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(width: 0.5)
        }
        .navigationTitle("")
    }

    private var sidebarTitlebarControls: some View {
        HStack {
            Spacer(minLength: 0)

            SidebarTitlebarToggleButton(help: "收合側邊欄", action: toggleSidebar)
        }
        .padding(.top, WindowChromeMetrics.appChromeTopInset)
        .padding(.horizontal, horizontalInset)
        .frame(height: WindowChromeMetrics.appChromeHeight, alignment: .top)
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DashboardTheme.ink)
                        .frame(width: 30, height: 30)

                    Capsule(style: .continuous)
                        .fill(DashboardTheme.orange)
                        .frame(width: 21, height: 8)
                        .offset(y: 5)

                    Circle()
                        .fill(DashboardTheme.cream)
                        .frame(width: 4, height: 4)
                        .offset(y: 18)
                }

                Text("Usage Watcher")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text("CPA · トークン使用量")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
                .tracking(1.0)
        }
    }

    private var localServiceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("本地服務")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)

            HStack(spacing: 6) {
                Circle()
                    .fill(hasLoadedData ? DashboardTheme.green : DashboardTheme.yellow)
                    .frame(width: 8, height: 8)
                    .shadow(color: (hasLoadedData ? DashboardTheme.green : DashboardTheme.yellow).opacity(0.24), radius: 3)

                Text(baseURL)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Keychain · admin_key ✓")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DashboardTheme.panelRaised.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DashboardTheme.hairline, lineWidth: 1)
        )
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
                .tracking(1.1)
                .padding(.horizontal, 4)

            VStack(spacing: 2) {
                content
            }
        }
    }
}

private struct SidebarItem<Accessory: View>: View {
    let title: String
    let systemImage: String
    var isActive = false
    var badge: String?
    let action: () -> Void
    let accessory: Accessory
    @State private var isHovered = false

    init(
        title: String,
        systemImage: String,
        isActive: Bool = false,
        badge: String? = nil,
        action: @escaping () -> Void = {},
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.badge = badge
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? DashboardTheme.orange : DashboardTheme.mutedInk)
                    .frame(width: 17, height: 17)

                Text(title)
                    .font(.system(size: 14, weight: isActive ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isActive ? DashboardTheme.cream : DashboardTheme.mutedInk)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? DashboardTheme.ink : DashboardTheme.softInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isActive ? DashboardTheme.yellow : DashboardTheme.panelRaised.opacity(0.72))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(DashboardTheme.hairline, lineWidth: 1)
                        )
                }

                accessory
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
    }

    private var rowBackground: Color {
        if isActive {
            return DashboardTheme.ink
        }
        return isHovered ? DashboardTheme.panelRaised.opacity(0.58) : Color.clear
    }
}

private struct LiveBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(DashboardTheme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(DashboardTheme.yellow)
            )
    }
}
