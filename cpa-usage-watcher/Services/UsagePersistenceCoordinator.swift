import Foundation

nonisolated struct UsagePersistenceJob: @unchecked Sendable {
    let payload: UsageRawPayload
    let events: [RequestEvent]
    let quotaSnapshots: [CredentialQuotaSnapshot]
    let timeRange: UsageTimeRange
    let fetchedAt: Date
}

nonisolated protocol UsagePersistenceWriting: AnyObject, Sendable {
    func persist(job: UsagePersistenceJob) throws
    func dashboardSnapshot(
        in timeRange: UsageTimeRange,
        prices: [ModelPriceSetting],
        basis: CostCalculationBasis,
        now: Date,
        calendar: Calendar,
        trendGranularity: TrendGranularity?
    ) throws -> UsageSnapshot
}

nonisolated protocol UsagePersistenceCoordinating: AnyObject {
    func dashboardSnapshot(
        in timeRange: UsageTimeRange,
        prices: [ModelPriceSetting],
        basis: CostCalculationBasis,
        now: Date,
        calendar: Calendar,
        trendGranularity: TrendGranularity?
    ) throws -> UsageSnapshot
    func enqueue(_ job: UsagePersistenceJob)
    func waitForPendingWrites() async
    func lastPersistenceError() -> Error?
}

nonisolated final class UsagePersistenceCoordinator: UsagePersistenceCoordinating, @unchecked Sendable {
    private let writer: UsagePersistenceWriting
    private let stateLock = NSLock()
    private let writerLock = NSLock()
    private var pendingWrite: Task<Void, Never>?
    private var pendingWriteGeneration = 0
    private var latestPersistenceError: Error?

    init(writer: UsagePersistenceWriting) {
        self.writer = writer
    }

    convenience init(store: UsageSQLiteStore) {
        self.init(writer: store)
    }

    func dashboardSnapshot(
        in timeRange: UsageTimeRange = .all,
        prices: [ModelPriceSetting] = [],
        basis: CostCalculationBasis = .defaultSelection,
        now: Date = Date(),
        calendar: Calendar = .current,
        trendGranularity: TrendGranularity? = nil
    ) throws -> UsageSnapshot {
        try writerLock.withLock {
            try writer.dashboardSnapshot(
                in: timeRange,
                prices: prices,
                basis: basis,
                now: now,
                calendar: calendar,
                trendGranularity: trendGranularity
            )
        }
    }

    func enqueue(_ job: UsagePersistenceJob) {
        stateLock.withLock {
            let previousWrite = pendingWrite
            pendingWriteGeneration += 1
            let generation = pendingWriteGeneration
            let writer = writer
            let writerLock = writerLock
            let task = Task.detached(priority: .utility) { [weak self, previousWrite, writer, writerLock, job, generation] in
                await previousWrite?.value

                let persistenceError: Error? = writerLock.withLock {
                    do {
                        try writer.persist(job: job)
                        return nil
                    } catch {
                        return error
                    }
                }

                if let persistenceError {
                    self?.recordPersistenceError(persistenceError)
                }
                self?.markWriteCompleted(generation: generation)
            }
            pendingWrite = task
        }
    }

    func waitForPendingWrites() async {
        while true {
            let task = stateLock.withLock { pendingWrite }
            guard let task else {
                return
            }
            await task.value

            let isDrained = stateLock.withLock { pendingWrite == nil }
            if isDrained {
                return
            }
        }
    }

    func lastPersistenceError() -> Error? {
        stateLock.withLock {
            latestPersistenceError
        }
    }

    private func recordPersistenceError(_ error: Error) {
        stateLock.withLock {
            latestPersistenceError = error
        }
        NSLog("Usage persistence failed: %@", String(describing: error))
    }

    private func markWriteCompleted(generation: Int) {
        stateLock.withLock {
            if pendingWriteGeneration == generation {
                pendingWrite = nil
            }
        }
    }
}

extension UsageSQLiteStore: UsagePersistenceWriting {
    nonisolated func persist(job: UsagePersistenceJob) throws {
        try upsert(events: job.events)
        try saveRawFetch(payload: job.payload, timeRange: job.timeRange, fetchedAt: job.fetchedAt)
        try upsert(quotaSnapshots: job.quotaSnapshots)
    }
}
