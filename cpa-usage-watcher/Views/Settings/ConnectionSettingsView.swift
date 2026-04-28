import SwiftUI

struct ConnectionSettingsView: View {
    @ObservedObject var viewModel: UsageDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL: String
    @State private var managementKey: String
    @State private var displayCurrency: DisplayCurrency
    @State private var exchangeRateText: String
    @State private var costCalculationBasis: CostCalculationBasis
    @State private var localError: String?
    @State private var isTestingConnection = false

    init(viewModel: UsageDashboardViewModel) {
        self.viewModel = viewModel
        _baseURL = State(initialValue: viewModel.connectionSettings.baseURL)
        _managementKey = State(initialValue: viewModel.connectionSettings.managementKey)
        _displayCurrency = State(initialValue: viewModel.displayCurrency)
        _exchangeRateText = State(initialValue: Self.formattedExchangeRate(viewModel.usdToCNYExchangeRate))
        _costCalculationBasis = State(initialValue: viewModel.costCalculationBasis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    billingSection
                    serviceSection

                    if let localError {
                        DashboardStatusBanner(
                            kind: .error,
                            message: localError,
                            dismiss: { self.localError = nil }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)

            Divider()

            actions
        }
        .frame(width: 560, height: 620)
        .background(DashboardTheme.panel)
        .onAppear(perform: syncDrafts)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tweaks · 收費標準")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.ink)

                Text("貨幣、價格計算與本地管理服務")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DashboardTheme.softInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("關閉")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(DashboardTheme.sidebar)
    }

    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("貨幣 / 計算")

            fieldLabel("顯示貨幣")
            SettingsSegmentedControl(
                options: DisplayCurrency.allCases.map { SettingsSegmentOption(value: $0, title: $0.title) },
                selection: $displayCurrency
            )

            HStack(spacing: 10) {
                Text("USD → CNY 匯率")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)

                Spacer(minLength: 12)

                TextField("", text: $exchangeRateText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(DashboardTheme.ink)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(width: 120)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(DashboardTheme.panelRaised.opacity(0.86))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DashboardTheme.hairline, lineWidth: 1)
            )

            fieldLabel("計算依據")
                .padding(.top, 6)
            SettingsSegmentedControl(
                options: CostCalculationBasis.allCases.map { SettingsSegmentOption(value: $0, title: $0.title) },
                selection: $costCalculationBasis
            )
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("本地服務")

            fieldLabel("Base URL")
            TextField("Base URL", text: $baseURL)
                .textContentType(.URL)
                .settingsFieldStyle()

            fieldLabel("Management Key")
            SecureField("Management Key", text: $managementKey)
                .textContentType(.password)
                .settingsFieldStyle()

            Text("默认地址为 \(ConnectionSettings.defaultBaseURL)。如果只填写服务 origin，会自动使用 /v0/management。管理密钥仅保存在本机钥匙串。")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.softInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("清除密钥", role: .destructive) {
                clearManagementKey()
            }
            .disabled(managementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            Button("测试连接") {
                Task {
                    await saveAndRefresh()
                }
            }
            .buttonStyle(DashboardChromeButtonStyle(accent: DashboardTheme.blue))
            .disabled(isTestingConnection)

            Button("保存") {
                save()
            }
            .buttonStyle(DashboardChromeButtonStyle(accent: DashboardTheme.ink, isProminent: true))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(DashboardTheme.sidebar)
    }

    private var draftSettings: ConnectionSettings {
        ConnectionSettings(baseURL: baseURL, managementKey: managementKey)
    }

    private var draftCostSettings: UsageCostDisplaySettings {
        UsageCostDisplaySettings(
            displayCurrency: displayCurrency,
            usdToCNYExchangeRate: parsedExchangeRate,
            calculationBasis: costCalculationBasis
        )
    }

    private var parsedExchangeRate: Double {
        let normalized = exchangeRateText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? UsageCostDisplaySettings.defaultUSDToCNYExchangeRate
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(DashboardTheme.softInk)
            .tracking(1.0)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(DashboardTheme.mutedInk)
    }

    private func save() {
        do {
            try viewModel.saveConnectionSettings(draftSettings)
            applyCostSettings()
            localError = nil
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func saveAndRefresh() async {
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            try viewModel.saveConnectionSettings(draftSettings)
            applyCostSettings()
            localError = nil
            await viewModel.refresh()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func clearManagementKey() {
        do {
            try viewModel.clearManagementKey()
            managementKey = ""
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }

    private func applyCostSettings() {
        let settings = draftCostSettings
        viewModel.setCostDisplaySettings(settings)
        exchangeRateText = Self.formattedExchangeRate(settings.usdToCNYExchangeRate)
    }

    private func syncDrafts() {
        baseURL = viewModel.connectionSettings.baseURL
        managementKey = viewModel.connectionSettings.managementKey
        displayCurrency = viewModel.displayCurrency
        exchangeRateText = Self.formattedExchangeRate(viewModel.usdToCNYExchangeRate)
        costCalculationBasis = viewModel.costCalculationBasis
    }

    private static func formattedExchangeRate(_ exchangeRate: Double) -> String {
        String(format: "%.2f", UsageCostDisplaySettings.sanitizeExchangeRate(exchangeRate))
    }
}

private struct SettingsSegmentOption<Value: Hashable>: Hashable {
    let value: Value
    let title: String
}

private struct SettingsSegmentedControl<Value: Hashable>: View {
    let options: [SettingsSegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardTheme.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == option.value {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DashboardTheme.panelRaised)
                            .shadow(color: DashboardTheme.shadow, radius: 4, y: 1)
                    }
                }
            }
        }
        .padding(2)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DashboardTheme.ink.opacity(0.06))
        )
    }
}

private extension View {
    func settingsFieldStyle() -> some View {
        self
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DashboardTheme.ink)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DashboardTheme.panelRaised.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DashboardTheme.hairline, lineWidth: 1)
            )
    }
}
