import SwiftUI

@main
struct cpa_usage_watcherApp: App {
    var body: some Scene {
        WindowGroup("CPA Usage Watcher · 使用統計") {
            ContentView()
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 1100)
    }
}
