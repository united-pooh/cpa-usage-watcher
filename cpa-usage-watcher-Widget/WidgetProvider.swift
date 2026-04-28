import WidgetKit

struct CpaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool

    init(date: Date, snapshot: WidgetSnapshot, isPlaceholder: Bool = false) {
        self.date = date
        self.snapshot = snapshot
        self.isPlaceholder = isPlaceholder
    }
}

struct CpaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CpaWidgetEntry {
        CpaWidgetEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (CpaWidgetEntry) -> Void) {
        let snap = context.isPreview ? .placeholder : WidgetSnapshot.load()
        completion(CpaWidgetEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CpaWidgetEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let entry = CpaWidgetEntry(date: Date(), snapshot: snap)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
