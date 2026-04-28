import SwiftUI

struct DashboardPanel<Accessory: View, Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DashboardTheme.orange)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DashboardTheme.compactRadius, style: .continuous)
                                .fill(DashboardTheme.orange.opacity(0.13))
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(DashboardTheme.ink)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.softInk)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 16)
                accessory
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                .fill(DashboardTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                .stroke(DashboardTheme.hairline, lineWidth: 1)
        )
    }
}

extension DashboardPanel where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            accessory: { EmptyView() },
            content: content
        )
    }
}

enum DashboardStatusTone {
    case neutral
    case success
    case warning
    case danger
    case accent

    var foreground: Color {
        switch self {
        case .neutral:
            DashboardTheme.mutedInk
        case .success:
            DashboardTheme.green
        case .warning:
            DashboardTheme.yellow
        case .danger:
            DashboardTheme.red
        case .accent:
            DashboardTheme.blue
        }
    }

    var background: Color {
        foreground.opacity(0.12)
    }
}

struct DashboardStatusBadge: View {
    let text: String
    var systemImage: String?
    var tone: DashboardStatusTone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }

            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tone.background)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tone.foreground.opacity(0.18), lineWidth: 1)
        )
    }
}

struct DashboardStatusBanner: View {
    enum Kind {
        case success
        case error
        case info

        var tone: DashboardStatusTone {
            switch self {
            case .success:
                .success
            case .error:
                .danger
            case .info:
                .accent
            }
        }

        var systemImage: String {
            switch self {
            case .success:
                "checkmark.circle"
            case .error:
                "exclamationmark.triangle"
            case .info:
                "info.circle"
            }
        }
    }

    let kind: Kind
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tone.foreground)

            Text(message)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("关闭")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.cornerRadius, style: .continuous)
                .fill(DashboardTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.cornerRadius, style: .continuous)
                .stroke(kind.tone.foreground.opacity(0.32), lineWidth: 1)
        )
    }
}

struct DashboardEmptyStateView: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.cornerRadius, style: .continuous)
                .fill(DashboardTheme.panelRaised.opacity(0.52))
        )
    }
}

struct DashboardLoadingOverlay: View {
    var message: String = "正在加载用量数据"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.cornerRadius, style: .continuous)
                .fill(DashboardTheme.panelRaised)
                .shadow(color: DashboardTheme.shadow, radius: 18, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.cornerRadius, style: .continuous)
                .stroke(DashboardTheme.hairline, lineWidth: 1)
        )
    }
}
