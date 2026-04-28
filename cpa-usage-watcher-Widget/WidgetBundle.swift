import WidgetKit
import SwiftUI

@main
struct CpaWidgetBundle: WidgetBundle {
    var body: some Widget {
        TotalRequestsWidget()
        TotalTokensWidget()
        ThroughputWidget()
        CacheThinkingWidget()
        TotalCostWidget()
    }
}

struct TotalRequestsWidget: Widget {
    let kind = "cpa.widget.requests"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CpaWidgetProvider()) { entry in
            TotalRequestsWidgetView(entry: entry)
        }
        .configurationDisplayName("總請求數")
        .description("顯示API請求總數及RPM")
        .supportedFamilies([.systemSmall])
    }
}

struct TotalTokensWidget: Widget {
    let kind = "cpa.widget.tokens"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CpaWidgetProvider()) { entry in
            TotalTokensWidgetView(entry: entry)
        }
        .configurationDisplayName("總 TOKEN")
        .description("顯示Token總數及TPM")
        .supportedFamilies([.systemSmall])
    }
}

struct ThroughputWidget: Widget {
    let kind = "cpa.widget.throughput"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CpaWidgetProvider()) { entry in
            ThroughputWidgetView(entry: entry)
        }
        .configurationDisplayName("RPM / TPM")
        .description("顯示吞吐量及延遲")
        .supportedFamilies([.systemSmall])
    }
}

struct CacheThinkingWidget: Widget {
    let kind = "cpa.widget.cache"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CpaWidgetProvider()) { entry in
            CacheThinkingWidgetView(entry: entry)
        }
        .configurationDisplayName("緩存 / 思考")
        .description("顯示緩存命中率及推理Token")
        .supportedFamilies([.systemSmall])
    }
}

struct TotalCostWidget: Widget {
    let kind = "cpa.widget.cost"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CpaWidgetProvider()) { entry in
            TotalCostWidgetView(entry: entry)
        }
        .configurationDisplayName("總花費")
        .description("顯示API總花費")
        .supportedFamilies([.systemSmall])
    }
}
