import SwiftUI
import UniformTypeIdentifiers

struct UsageDashboardView: View {
    private static let heroTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @ObservedObject var viewModel: UsageDashboardViewModel
    @Binding private var sidebarVisibility: NavigationSplitViewVisibility
    @Binding private var selectedSection: DashboardSection
    @Binding private var selectedSidebarItem: SidebarSelection
    @Binding private var navigationRequest: DashboardAnchor?
    @Binding private var isShowingSettings: Bool
    private let chromeLeadingInset: CGFloat

    @State private var isShowingImporter = false
    @State private var isShowingExporter = false
    @State private var exportDocument = UsageExportDocument()
    @State private var isFileOperationRunning = false

    init(
        viewModel: UsageDashboardViewModel,
        sidebarVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all),
        selectedSection: Binding<DashboardSection> = .constant(.overview),
        selectedSidebarItem: Binding<SidebarSelection> = .constant(.overview),
        navigationRequest: Binding<DashboardAnchor?> = .constant(nil),
        isShowingSettings: Binding<Bool> = .constant(false),
        chromeLeadingInset: CGFloat = 0
    ) {
        self.viewModel = viewModel
        self._sidebarVisibility = sidebarVisibility
        self._selectedSection = selectedSection
        self._selectedSidebarItem = selectedSidebarItem
        self._navigationRequest = navigationRequest
        self._isShowingSettings = isShowingSettings
        self.chromeLeadingInset = chromeLeadingInset
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 780

            ZStack {
                DashboardTheme.cream
                    .ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    VStack(spacing: 0) {
                        windowChromeBar(isCompact: isCompact)
                        sectionTabs(scrollProxy: scrollProxy, isCompact: isCompact)

                        ScrollView {
                            VStack(alignment: .leading, spacing: isCompact ? 18 : 22) {
                                dashboardMessages

                                dashboardHero(isCompact: isCompact, availableWidth: proxy.size.width)
                                    .id(DashboardSection.overview.id)

                                MetricRibbonView(viewModel: viewModel)
                                    .id(DashboardAnchor.health.id)

                                SectionHeader(
                                    number: "01",
                                    title: "趨勢與分布",
                                    subtitle: "トレンド · 分布",
                                    kicker: "TRENDS · DISTRIBUTION",
                                    accent: DashboardTheme.orange
                                )
                                UsageTrendChartsView(viewModel: viewModel)

                                SectionHeader(
                                    number: "02",
                                    title: "API・模型統計",
                                    subtitle: "エンドポイント別",
                                    kicker: "ENDPOINTS · MODELS",
                                    accent: DashboardTheme.orange
                                )
                                .id(DashboardSection.models.id)
                                endpointModelSections

                                SectionHeader(
                                    number: "03",
                                    title: "請求事件明細",
                                    subtitle: "リクエストログ",
                                    kicker: "REQUEST LOG",
                                    accent: DashboardTheme.orange
                                )
                                .id(DashboardSection.events.id)
                                requestEventSection

                                SectionHeader(
                                    number: "04",
                                    title: "憑證・價格",
                                    subtitle: "クレデンシャル · 価格",
                                    kicker: "CREDENTIALS · PRICING",
                                    accent: DashboardTheme.orange
                                )
                                .id(DashboardSection.prices.id)
                                credentialsPricingSection

                                footer
                            }
                            .padding(.horizontal, isCompact ? 18 : 32)
                            .padding(.top, isCompact ? 18 : 30)
                            .padding(.bottom, 30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .onChange(of: navigationRequest) { _, anchor in
                        guard let anchor else {
                            return
                        }
                        scrollTo(anchor.section, targetID: anchor.id, with: scrollProxy, syncSidebarSelection: false)
                        navigationRequest = nil
                    }
                }

                if viewModel.isLoading && !viewModel.hasLoadedData {
                    DashboardLoadingOverlay()
                }
            }
        }
        .navigationTitle("CPA Usage Watcher · 使用統計")
        .sheet(isPresented: $isShowingSettings) {
            ConnectionSettingsView(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .fileExporter(
            isPresented: $isShowingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "usage-export.json"
        ) { result in
            if case let .failure(error) = result {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .task {
            await viewModel.loadStoredConnectionSettingsIfNeeded()
            guard !viewModel.hasLoadedData else {
                return
            }
            await viewModel.refresh()
        }
        .task(id: viewModel.refreshSettings) {
            guard viewModel.refreshSettings.isAutoRefreshEnabled else {
                return
            }
            let intervalNanoseconds = UInt64(viewModel.refreshSettings.intervalSeconds) * 1_000_000_000
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    // Cancelled — stop looping
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                await viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private func windowChromeBar(isCompact: Bool) -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    chromeTitle
                    Spacer(minLength: 12)
                    fullToolbar
                }

                VStack(alignment: .leading, spacing: 10) {
                    chromeTitle
                    compactToolbar
                }
            }
            .padding(.leading, horizontalChromeInset(isCompact: isCompact) + chromeLeadingInset)
            .padding(.trailing, horizontalChromeInset(isCompact: isCompact))
            .padding(.top, WindowChromeMetrics.appChromeTopInset)

            Spacer(minLength: 0)
        }
        .frame(height: isCompact ? WindowChromeMetrics.compactAppChromeHeight : WindowChromeMetrics.appChromeHeight, alignment: .top)
        .background(DashboardTheme.cream)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
    }

    private var chromeTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("使用統計")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(1)

            Text("使用状況ダッシュボード")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
                .lineLimit(1)
        }
    }

    private var fullToolbar: some View {
        HStack(spacing: 8) {
            rangeSegmentedPicker

            toolbarActionButton(
                "导入",
                systemImage: "tray.and.arrow.down",
                accent: DashboardTheme.orange,
                disabled: viewModel.isLoading || isFileOperationRunning
            ) {
                isShowingImporter = true
            }

            toolbarActionButton(
                "导出",
                systemImage: "square.and.arrow.up",
                accent: DashboardTheme.blue,
                disabled: viewModel.isLoading || isFileOperationRunning
            ) {
                Task {
                    await exportUsage()
                }
            }

            toolbarActionButton(
                "刷新",
                systemImage: "arrow.clockwise",
                accent: DashboardTheme.ink,
                disabled: viewModel.isLoading,
                prominent: true
            ) {
                Task {
                    await viewModel.refresh()
                }
            }

            toolbarActionButton(
                viewModel.sensitiveValuesToggleTitle,
                systemImage: viewModel.sensitiveValuesToggleIcon,
                accent: DashboardTheme.orange
            ) {
                viewModel.toggleSensitiveValuesMask()
            }

            toolbarActionButton(
                "设置",
                systemImage: "gearshape",
                accent: DashboardTheme.blue
            ) {
                isShowingSettings = true
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(connectionBadgeTone.foreground)
                    .frame(width: 7, height: 7)
                Text(UsageFormatters.shortTime(viewModel.lastUpdatedAt ?? Date()))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DashboardTheme.softInk)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 6)
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            rangeMenuPicker

            Spacer(minLength: 4)

            compactIconButton("导入", systemImage: "tray.and.arrow.down", accent: DashboardTheme.orange) {
                isShowingImporter = true
            }
            .disabled(viewModel.isLoading || isFileOperationRunning)

            compactIconButton("导出", systemImage: "square.and.arrow.up", accent: DashboardTheme.blue) {
                Task {
                    await exportUsage()
                }
            }
            .disabled(viewModel.isLoading || isFileOperationRunning)

            compactIconButton("刷新", systemImage: "arrow.clockwise", accent: DashboardTheme.green) {
                Task {
                    await viewModel.refresh()
                }
            }
            .disabled(viewModel.isLoading)

            compactIconButton(viewModel.sensitiveValuesToggleTitle, systemImage: viewModel.sensitiveValuesToggleIcon, accent: DashboardTheme.yellow) {
                viewModel.toggleSensitiveValuesMask()
            }

            compactIconButton("设置", systemImage: "gearshape", accent: DashboardTheme.blue) {
                isShowingSettings = true
            }
        }
    }

    private var rangeSegmentedPicker: some View {
        Picker("时间范围", selection: $viewModel.selectedTimeRange) {
            ForEach(viewModel.timeRangeOptions) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.menu)
        .tint(DashboardTheme.orange)
        .frame(minWidth: 194, idealWidth: 204, maxWidth: 220)
    }

    private var rangeMenuPicker: some View {
        Picker("时间范围", selection: $viewModel.selectedTimeRange) {
            ForEach(viewModel.timeRangeOptions) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.menu)
        .tint(DashboardTheme.orange)
        .frame(minWidth: 194, idealWidth: 204, maxWidth: 220)
    }

    private func toolbarActionButton(
        _ title: String,
        systemImage: String,
        accent: Color,
        disabled: Bool = false,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(DashboardChromeButtonStyle(accent: accent, isProminent: prominent))
        .disabled(disabled)
        .help(title)
    }

    private func compactIconButton(
        _ title: String,
        systemImage: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(DashboardIconButtonStyle(accent: accent))
        .help(title)
    }

    private func sectionTabs(scrollProxy: ScrollViewProxy, isCompact: Bool) -> some View {
        HStack(spacing: 32) {
            ForEach(DashboardSection.allCases) { section in
                Button {
                    scrollTo(section, with: scrollProxy)
                } label: {
                    HStack(spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 14, weight: selectedSection == section ? .black : .semibold, design: .rounded))
                        Text(section.japaneseTitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(selectedSection == section ? DashboardTheme.orangeDeep : DashboardTheme.softInk)
                    }
                    .foregroundStyle(selectedSection == section ? DashboardTheme.ink : DashboardTheme.mutedInk.opacity(0.76))
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selectedSection == section ? DashboardTheme.orange : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .help(section.subtitle)
            }
        }
        .padding(.leading, horizontalChromeInset(isCompact: isCompact) + chromeLeadingInset)
        .padding(.trailing, horizontalChromeInset(isCompact: isCompact))
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.cream)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
    }

    private func horizontalChromeInset(isCompact: Bool) -> CGFloat {
        isCompact ? WindowChromeMetrics.compactAppChromeHorizontalInset : WindowChromeMetrics.appChromeHorizontalInset
    }

    private func scrollTo(
        _ section: DashboardSection,
        targetID: String? = nil,
        with scrollProxy: ScrollViewProxy,
        syncSidebarSelection: Bool = true
    ) {
        selectedSection = section
        if syncSidebarSelection {
            selectedSidebarItem = section.sidebarSelection
        }
        withAnimation(.easeInOut(duration: 0.24)) {
            scrollProxy.scrollTo(targetID ?? section.id, anchor: .top)
        }
    }

    private func dashboardHero(isCompact: Bool, availableWidth: CGFloat) -> some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 20) {
                    heroCopy(isCompact: true)
                    heroCostCard(isCompact: true)
                }
            } else {
                HStack(alignment: .top, spacing: 42) {
                    heroCopy(isCompact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    heroCostCard(isCompact: false)
                        .frame(width: min(720, max(480, availableWidth * 0.38)))
                }
            }
        }
        .padding(.top, isCompact ? 10 : 12)
        .padding(.bottom, isCompact ? 10 : 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroChipRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                HeroChip(text: heroEndpointChipText, leadingDot: DashboardTheme.green)
                HeroChip(text: heroUpdatedChipText)
                HeroChip(text: heroRangeChipText)
            }

            VStack(alignment: .leading, spacing: 8) {
                HeroChip(text: heroEndpointChipText, leadingDot: DashboardTheme.green)
                HeroChip(text: heroUpdatedChipText)
                HeroChip(text: heroRangeChipText)
            }
        }
    }

    private func heroCopy(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {
            VStack(alignment: .leading, spacing: isCompact ? -9 : -18) {
                Text("Token")
                    .font(.system(size: isCompact ? 62 : 96, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.46)

                Text("用量速報。")
                    .font(.system(size: isCompact ? 58 : 92, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
            }

            heroChipRow

            Text("USAGE / DASHBOARD / 使用統計")
                .font(.system(size: isCompact ? 12 : 14, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.softInk)
                .tracking(5)
                .lineLimit(1)
        }
    }

    private func heroCostCard(isCompact: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 18) {
            ZStack {
                HStack(alignment: .center) {
                    Text("夏のトークン記録")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardTheme.orangeDeep)
                        .rotationEffect(.degrees(-8))

                    Spacer()

                    Text("SUMMER · ’26")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.orange)
                        .tracking(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(DashboardTheme.orange, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        )
                        .rotationEffect(.degrees(4))
                }

                Circle()
                    .fill(DashboardTheme.blue.opacity(0.66))
                    .frame(width: isCompact ? 30 : 36, height: isCompact ? 30 : 36)
                    .offset(x: isCompact ? -66 : -118, y: -14)

                Circle()
                    .fill(DashboardTheme.yellow)
                    .frame(width: isCompact ? 13 : 16, height: isCompact ? 13 : 16)
                    .offset(x: isCompact ? -34 : -78, y: 18)
            }
            .frame(height: isCompact ? 38 : 52)

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: isCompact ? 32 : 44, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.804, green: 0.918, blue: 0.985),
                                Color(red: 0.902, green: 0.961, blue: 0.988)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: isCompact ? 63 : 88, style: .continuous)
                    .fill(DashboardTheme.orange.opacity(0.54))
                    .frame(width: isCompact ? 126 : 176, height: isCompact ? 126 : 176)
                    .blur(radius: 5)
                    .offset(x: isCompact ? 34 : 48, y: isCompact ? -22 : -34)

                VStack(alignment: .leading, spacing: isCompact ? 15 : 20) {
                    HStack {
                        Text("TOTAL · 總花費")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(Color(red: 0.030, green: 0.318, blue: 0.439))
                            .tracking(3)
                        Spacer()
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 9) {
                        Text(heroCostValueText)
                            .font(.system(size: isCompact ? 48 : 66, weight: .black, design: .rounded))
                            .foregroundStyle(DashboardTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.54)
                        Text(heroCurrencyText)
                            .font(.system(size: isCompact ? 16 : 20, weight: .black, design: .rounded))
                            .foregroundStyle(DashboardTheme.mutedInk)
                    }

                    HeroDeltaPill(text: heroStatusPillText)

                    Spacer(minLength: 0)

                    HStack(alignment: .bottom) {
                        Text(heroSavedPricesText)
                            .font(.system(size: isCompact ? 12 : 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.030, green: 0.318, blue: 0.439))
                            .tracking(2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Spacer()

                        Text(heroCostBasisText)
                            .font(.system(size: isCompact ? 13 : 15, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.030, green: 0.318, blue: 0.439))
                            .lineLimit(1)
                    }
                }
                .padding(isCompact ? 24 : 32)
            }
            .frame(minHeight: isCompact ? 228 : 260)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 32 : 44, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 32 : 44, style: .continuous)
                    .stroke(DashboardTheme.strongHairline.opacity(0.52), lineWidth: 1)
            )
        }
    }

    private var hasUsageActivity: Bool {
        viewModel.displaySnapshot.summary.totalRequests > 0
            || viewModel.displaySnapshot.summary.totalTokens > 0
            || !viewModel.displaySnapshot.events.isEmpty
    }

    private var heroEndpointChipText: String {
        return "\(UsageFormatters.integer(viewModel.displaySnapshot.endpoints.count)) endpoints 在线"
    }

    private var heroUpdatedChipText: String {
        let updatedAt = viewModel.lastUpdatedAt.map(heroTimeText) ?? "尚未更新"
        return "最近更新 · \(updatedAt)"
    }

    private var heroRangeChipText: String {
        "數據範圍 · \(displayTitle(for: viewModel.selectedTimeRange))"
    }

    private var heroCostValueText: String {
        if let totalCost = viewModel.displaySnapshot.summary.totalCost {
            return viewModel.formattedCost(totalCost, placeholder: "未配置", fractionLength: 0)
        }

        if !hasUsageActivity {
            return viewModel.formattedCost(0, placeholder: "未配置", fractionLength: 0)
        }

        return "未配置"
    }

    private var heroCurrencyText: String {
        viewModel.displayCurrency.rawValue
    }

    private var heroSavedPricesText: String {
        let label = viewModel.costCalculationBasis == .saved ? "SAVED PRICES" : "ESTIMATE"
        return "\(label) · \(viewModel.sortedModelPrices.count) / \(max(viewModel.displaySnapshot.models.count, viewModel.sortedModelPrices.count))"
    }

    private var heroCostBasisText: String {
        return viewModel.costCalculationBasis == .saved ? "從價格表計算" : "從紀錄估算"
    }

    private var heroStatusPillText: String {
        if viewModel.isLoading {
            return "同步中 · \(displayTitle(for: viewModel.selectedTimeRange))"
        }

        if viewModel.hasLoadedData {
            return hasUsageActivity ? "实时数据 · \(displayTitle(for: viewModel.selectedTimeRange))" : "已连接 · 暂无用量"
        }

        return "等待连接"
    }

    private func displayTitle(for timeRange: UsageTimeRange) -> String {
        switch timeRange {
        case .all:
            "全部時間"
        case .last7Hours:
            "最近 7 小時"
        case .last24Hours:
            "最近 24 小時"
        case .last7Days:
            "最近 7 天"
        }
    }

    private func heroTimeText(_ date: Date) -> String {
        Self.heroTimeFormatter.string(from: date)
    }

    @ViewBuilder
    private var dashboardMessages: some View {
        if let errorMessage = viewModel.errorMessage ?? viewModel.loadState.errorMessage {
            DashboardStatusBanner(
                kind: .error,
                message: errorMessage,
                actionTitle: "重试",
                action: {
                    Task {
                        await viewModel.refresh()
                    }
                },
                dismiss: viewModel.clearMessages
            )
        }
    }

    private var endpointModelSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            TableWidgetSection {
                EndpointStatsTableWidget(viewModel: viewModel)
            }

            TableWidgetSection {
                ModelStatsTableWidget(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var requestEventSection: some View {
        TableWidgetSection {
            RequestEventsTableWidget(viewModel: viewModel)
        }
    }

    private var credentialsPricingSection: some View {
        HStack(alignment: .top, spacing: 20) {
            TableWidgetSection {
                CredentialStatsTableWidget(viewModel: viewModel)
                    .frame(minHeight: 650, alignment: .top)
            }
            .id(DashboardAnchor.credentials.id)
            .frame(maxWidth: .infinity, alignment: .top)

            TableWidgetSection {
                ModelPriceSettingsTableWidget(viewModel: viewModel)
                    .frame(minHeight: 650, alignment: .top)
            }
            .id(DashboardAnchor.priceEditor.id)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("CPA USAGE WATCHER · v1.0 · macOS 14+")
            Spacer()
            Text("build 2026.04.27 · sha:e91a · 夏")
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(DashboardTheme.softInk)
        .tracking(3)
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            TableWidgetSection {
                ModelPriceSettingsTableWidget(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionBadgeText: String {
        if viewModel.isLoading {
            return "刷新中"
        }
        if viewModel.hasLoadedData {
            return "已连接"
        }
        return viewModel.connectionSettings.hasManagementKey ? "待刷新" : "需要密钥"
    }

    private var connectionBadgeIcon: String {
        if viewModel.isLoading {
            return "arrow.triangle.2.circlepath"
        }
        if viewModel.hasLoadedData {
            return "checkmark.circle"
        }
        return viewModel.connectionSettings.hasManagementKey ? "circle.dashed" : "key"
    }

    private var connectionBadgeTone: DashboardStatusTone {
        if viewModel.isLoading {
            return .warning
        }
        if viewModel.hasLoadedData {
            return .success
        }
        return viewModel.connectionSettings.hasManagementKey ? .neutral : .warning
    }

    private func exportUsage() async {
        isFileOperationRunning = true
        defer { isFileOperationRunning = false }

        do {
            let data = try await viewModel.exportUsage()
            exportDocument = UsageExportDocument(data: data)
            isShowingExporter = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            Task {
                await importUsage(from: url)
            }
        case let .failure(error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func importUsage(from url: URL) async {
        isFileOperationRunning = true
        defer { isFileOperationRunning = false }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: url)
            }.value
            let contentType = importContentType(for: url)
            _ = try await viewModel.importUsage(data, contentType: contentType)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func importContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "csv":
            "text/csv"
        case "txt", "text":
            "text/plain"
        default:
            "application/json"
        }
    }
}

private struct TableWidgetSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                    .fill(DashboardTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                    .stroke(DashboardTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous))
    }
}

enum DashboardAnchor: String, Hashable {
    case overview
    case health
    case models
    case events
    case credentials
    case priceEditor

    var id: String {
        switch self {
        case .overview:
            DashboardSection.overview.id
        case .models:
            DashboardSection.models.id
        case .events:
            DashboardSection.events.id
        case .health:
            "service-health"
        case .credentials:
            "credentials-panel"
        case .priceEditor:
            "price-editor-panel"
        }
    }

    var section: DashboardSection {
        switch self {
        case .overview, .health:
            .overview
        case .models:
            .models
        case .events:
            .events
        case .credentials, .priceEditor:
            .prices
        }
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case models
    case events
    case prices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "儀表盤"
        case .events:
            "請求事件"
        case .models:
            "模型統計"
        case .prices:
            "價格設置"
        }
    }

    var japaneseTitle: String {
        switch self {
        case .overview:
            "ダッシュボード"
        case .events:
            "ログ"
        case .models:
            "モデル"
        case .prices:
            "価格"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            "跳转到总览"
        case .events:
            "跳转到请求事件"
        case .models:
            "跳转到模型统计"
        case .prices:
            "跳转到价格"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.3.group"
        case .events:
            "doc.text"
        case .models:
            "tablecells"
        case .prices:
            "tag"
        }
    }

    var sidebarSelection: SidebarSelection {
        switch self {
        case .overview:
            .overview
        case .events:
            .events
        case .models:
            .models
        case .prices:
            .prices
        }
    }

    var accent: Color {
        switch self {
        case .overview:
            DashboardTheme.orange
        case .events:
            DashboardTheme.blue
        case .models:
            DashboardTheme.green
        case .prices:
            DashboardTheme.yellow
        }
    }
}

private struct SectionHeader: View {
    let number: String
    let title: String
    let subtitle: String
    let kicker: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                Text(number)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 20)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DashboardTheme.orangeSoft.opacity(0.82))
                    )

                Text(title)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(kicker)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DashboardTheme.softInk)
                    .tracking(5)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(DashboardTheme.hairline)
                .frame(height: 0.5)
        }
        .padding(.top, 4)
    }
}

private struct HeroChip: View {
    let text: String
    var leadingDot: Color?

    var body: some View {
        HStack(spacing: 7) {
            if let leadingDot {
                Circle()
                    .fill(leadingDot)
                    .frame(width: 8, height: 8)
            }

            Text(text)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.mutedInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(DashboardTheme.paper)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(DashboardTheme.strongHairline.opacity(0.70), lineWidth: 1)
        )
    }
}

private struct HeroDeltaPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt")
                .font(.system(size: 12, weight: .bold))

            Text(text)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(DashboardTheme.orangeDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.70))
        )
    }
}

private struct HeroFactPill: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(DashboardTheme.mutedInk)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DashboardTheme.cornerRadius,
                        bottomLeadingRadius: DashboardTheme.cornerRadius
                    )
                )
        }
    }
}

struct UsageExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .commaSeparatedText, .plainText]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
