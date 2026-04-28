import SwiftUI

struct MetricProgressSegment {
    let value: Double
    let color: Color

    init(_ value: Double, color: Color) {
        self.value = value
        self.color = color
    }
}

struct MetricTileView: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let systemImage: String
    let tint: Color
    var details: [String] = []
    var footer: String?
    var progressSegments: [MetricProgressSegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardTheme.softInk)
                    .tracking(2.8)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DashboardTheme.softInk)
                        .lineLimit(1)
                }
            }

            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(DashboardTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.54)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DashboardTheme.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            if hasProgressSlot {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    if let footer, !footer.isEmpty {
                        Text(footer)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    MetricProgressBar(segments: progressSegments, fallbackTint: tint)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                .fill(DashboardTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous)
                .stroke(DashboardTheme.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 70, height: 70)
                    .offset(x: 20, y: -22)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DashboardTheme.paper.opacity(0.72))
                    )
                    .offset(x: -12, y: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardRadius, style: .continuous))
    }

    private var hasProgressSlot: Bool {
        if let footer, !footer.isEmpty {
            return true
        }
        return !progressSegments.isEmpty
    }
}

private struct MetricProgressBar: View {
    let segments: [MetricProgressSegment]
    let fallbackTint: Color

    private var activeSegments: [MetricProgressSegment] {
        segments.filter { $0.value.isFinite && $0.value > 0 }
    }

    private var total: Double {
        activeSegments.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(DashboardTheme.paperDeep.opacity(0.82))

                if total > 0 {
                    HStack(spacing: 2) {
                        ForEach(Array(activeSegments.enumerated()), id: \.offset) { _, segment in
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(segment.color)
                                .frame(width: max(5, proxy.size.width * segment.value / total))
                        }
                    }
                    .clipShape(Capsule(style: .continuous))
                } else {
                    Capsule(style: .continuous)
                        .fill(fallbackTint.opacity(0.26))
                        .frame(width: 16)
                }
            }
        }
        .frame(height: 5)
    }
}
