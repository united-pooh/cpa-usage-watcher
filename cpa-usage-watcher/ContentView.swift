import SwiftUI

struct ContentView: View {
    private let sidebarColumnWidth: CGFloat = 232

    @StateObject private var viewModel = UsageDashboardViewModel()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var didAutoCollapseSidebar = false
    @State private var selectedSection: DashboardSection = .overview
    @State private var selectedSidebarItem: SidebarSelection = .overview
    @State private var sectionNavigationRequest: DashboardAnchor?
    @State private var isShowingSettings = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                DashboardTheme.cream
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    if isSidebarVisible {
                        AppSidebarView(
                            snapshot: viewModel.displaySnapshot,
                            hasLoadedData: viewModel.hasLoadedData,
                            isLoading: viewModel.isLoading,
                            lastUpdatedAt: viewModel.lastUpdatedAt,
                            baseURL: viewModel.connectionSettings.baseURL,
                            selectedItem: selectedSidebarItem,
                            select: selectSidebarItem,
                            toggleSidebar: collapseSidebar
                        )
                        .frame(width: sidebarColumnWidth)
                        .ignoresSafeArea(.container, edges: .top)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    UsageDashboardView(
                        viewModel: viewModel,
                        sidebarVisibility: $sidebarVisibility,
                        selectedSection: $selectedSection,
                        selectedSidebarItem: $selectedSidebarItem,
                        navigationRequest: $sectionNavigationRequest,
                        isShowingSettings: $isShowingSettings,
                        chromeLeadingInset: isSidebarVisible ? 0 : WindowChromeMetrics.collapsedDetailLeadingInset
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)

                if !isSidebarVisible {
                    collapsedSidebarButton
                        .ignoresSafeArea(.container, edges: .top)
                }

                WindowTitlebarConfigurator()
                    .frame(width: 0, height: 0)
            }
            .frame(minWidth: 1360, minHeight: 900)
            .onAppear {
                updateSidebarVisibility(for: proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                updateSidebarVisibility(for: width)
            }
        }
    }

    private var isSidebarVisible: Bool {
        sidebarVisibility != .detailOnly
    }

    private var collapsedSidebarButton: some View {
        SidebarTitlebarToggleButton(help: "展開側邊欄", action: expandSidebar)
        .padding(.top, WindowChromeMetrics.appChromeTopInset)
        .padding(.leading, WindowChromeMetrics.collapsedSidebarButtonLeading)
    }

    private func updateSidebarVisibility(for width: CGFloat) {
        if width < 900, sidebarVisibility != .detailOnly {
            setSidebarVisibility(.detailOnly, animated: false)
            didAutoCollapseSidebar = true
        } else if width > 1080, didAutoCollapseSidebar {
            setSidebarVisibility(.all, animated: false)
            didAutoCollapseSidebar = false
        }
    }

    private func navigateTo(_ anchor: DashboardAnchor) {
        selectedSection = anchor.section
        sectionNavigationRequest = anchor
    }

    private func collapseSidebar() {
        setSidebarVisibility(.detailOnly)
        didAutoCollapseSidebar = false
    }

    private func expandSidebar() {
        setSidebarVisibility(.all)
        didAutoCollapseSidebar = false
    }

    private func setSidebarVisibility(_ visibility: NavigationSplitViewVisibility, animated: Bool = true) {
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                sidebarVisibility = visibility
            }
            return
        }

        withAnimation(.smooth(duration: 0.18)) {
            sidebarVisibility = visibility
        }
    }

    private func selectSidebarItem(_ item: SidebarSelection) {
        selectedSidebarItem = item

        switch item {
        case .overview:
            navigateTo(.overview)
        case .health:
            navigateTo(.health)
        case .events:
            navigateTo(.events)
        case .apiKeys:
            navigateTo(.credentials)
        case .prices:
            navigateTo(.priceEditor)
        case .models:
            navigateTo(.models)
        case .connection:
            isShowingSettings = true
        }
    }
}
