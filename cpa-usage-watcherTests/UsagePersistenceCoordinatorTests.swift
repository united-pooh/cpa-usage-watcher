import Foundation

enum UsagePersistenceCoordinatorTests {
    static func run() async throws {
        try await writesRunFIFOWithoutOverlap()
        await writeFailuresAreCapturedWithoutStoppingQueue()
    }

    private static func writesRunFIFOWithoutOverlap() async throws {
        let writer = CoordinatorTestWriter()
        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        writer.onWriteStarted = { id in
            if id == "first" {
                firstStarted.signal()
            }
        }
        writer.onWriteBlocked = { id in
            if id == "first" {
                releaseFirst.wait()
            }
        }
        let coordinator = UsagePersistenceCoordinator(writer: writer)

        coordinator.enqueue(job(id: "first"))
        try wait(for: firstStarted, message: "first write should start before second write is enqueued")
        coordinator.enqueue(job(id: "second"))
        releaseFirst.signal()
        await coordinator.waitForPendingWrites()

        TestExpect.equal(writer.attemptedIDs(), ["first", "second"], "queued persistence jobs should run FIFO")
        TestExpect.equal(writer.maxActiveWriteCount(), 1, "queued persistence jobs should not overlap")
    }

    private static func writeFailuresAreCapturedWithoutStoppingQueue() async {
        let writer = CoordinatorTestWriter(failingIDs: ["bad"])
        let coordinator = UsagePersistenceCoordinator(writer: writer)

        coordinator.enqueue(job(id: "bad"))
        coordinator.enqueue(job(id: "good"))
        await coordinator.waitForPendingWrites()

        TestExpect.equal(writer.attemptedIDs(), ["bad", "good"], "failed persistence jobs should not stop later queued jobs")
        TestExpect.equal(writer.completedIDs(), ["good"], "successful jobs after a failure should still complete")
        TestExpect.equal((coordinator.lastPersistenceError() as? CoordinatorTestError)?.id, "bad", "coordinator should remember the latest persistence error")
    }

    private static func wait(for semaphore: DispatchSemaphore, message: String) throws {
        if semaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
            throw TestFailure(message)
        }
    }

    private static func job(id: String) -> UsagePersistenceJob {
        let fetchedAt = Date(timeIntervalSince1970: 1_777_290_400)
        return UsagePersistenceJob(
            payload: UsageRawPayload(root: .object(["usageDetails": .array([])])),
            events: [
                RequestEvent(
                    id: id,
                    timestamp: fetchedAt,
                    endpoint: "/v1/messages",
                    model: "claude-sonnet",
                    source: "console-account",
                    provider: "anthropic",
                    authIndex: "account-a",
                    isSuccess: true,
                    latencyMs: 120,
                    inputTokens: 10,
                    outputTokens: 20,
                    totalTokens: 30
                )
            ],
            quotaSnapshots: [
                CredentialQuotaSnapshot(
                    id: "quota-\(id)",
                    credential: "account-a",
                    source: "console-account",
                    provider: "anthropic",
                    capturedAt: fetchedAt
                )
            ],
            timeRange: .last24Hours,
            fetchedAt: fetchedAt
        )
    }
}

private struct CoordinatorTestError: Error, Equatable {
    let id: String
}

private final class CoordinatorTestWriter: UsagePersistenceWriting, @unchecked Sendable {
    private let lock = NSLock()
    private let failingIDs: Set<String>
    private var activeWriteCount = 0
    private var highestActiveWriteCount = 0
    private var attemptedWriteIDs: [String] = []
    private var completedWriteIDs: [String] = []
    var onWriteStarted: ((String) -> Void)?
    var onWriteBlocked: ((String) -> Void)?

    init(failingIDs: Set<String> = []) {
        self.failingIDs = failingIDs
    }

    func persist(job: UsagePersistenceJob) throws {
        let id = job.events.first?.id ?? "missing-id"
        lock.lock()
        attemptedWriteIDs.append(id)
        activeWriteCount += 1
        highestActiveWriteCount = max(highestActiveWriteCount, activeWriteCount)
        lock.unlock()

        onWriteStarted?(id)
        onWriteBlocked?(id)

        defer {
            lock.lock()
            activeWriteCount -= 1
            lock.unlock()
        }

        if failingIDs.contains(id) {
            throw CoordinatorTestError(id: id)
        }

        lock.lock()
        completedWriteIDs.append(id)
        lock.unlock()
    }

    func dashboardSnapshot(
        in timeRange: UsageTimeRange,
        prices: [ModelPriceSetting],
        basis: CostCalculationBasis,
        now: Date,
        calendar: Calendar,
        trendGranularity: TrendGranularity?
    ) throws -> UsageSnapshot {
        UsageSnapshot(timeRange: timeRange, generatedAt: now, sourceDescription: "test")
    }

    func attemptedIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return attemptedWriteIDs
    }

    func completedIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return completedWriteIDs
    }

    func maxActiveWriteCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return highestActiveWriteCount
    }
}
