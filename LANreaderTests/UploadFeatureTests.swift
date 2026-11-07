import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class UploadFeatureTests: LANreaderTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    override func tearDownWithError() throws {
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    func testCheckJobStatusShowsCachedJobBeforeRefreshingIt() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let cachedJob = Self.makeJob(id: 7, lastUpdate: now.addingTimeInterval(-60))
        var storedJob = cachedJob
        try database.saveDownloadJob(&storedJob)
        let service = try await Self.configuredService()
        Self.stubJobStatus(id: 7, state: "finished", success: 1)

        let store = TestStore(initialState: UploadFeature.State()) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.date.now = now
        }
        store.timeout = .seconds(5)

        let task = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded) {
            $0.hasLoadedJobs = true
            $0.jobDetails[7] = cachedJob
        }

        let refreshedJob = Self.makeJob(
            id: 7,
            title: "Archive Title",
            isActive: false,
            isSuccess: true,
            message: "Done",
            lastUpdate: now
        )
        await store.receive(\.jobStatusUpdated) {
            $0.jobDetails[7] = refreshedJob
        }
        await task.finish()

        XCTAssertEqual(try database.readAllDownloadJobs(), [refreshedJob])
    }

    @MainActor
    func testCheckJobStatusKeepsFinishedJobsForADay() async throws {
        let database = try AppDatabase(DatabaseQueue())
        var expiredJob = Self.makeJob(
            id: 7,
            isActive: false,
            isSuccess: true,
            lastUpdate: now.addingTimeInterval(-24 * 60 * 60 - 1)
        )
        let completedJob = Self.makeJob(
            id: 8,
            isActive: false,
            isSuccess: true,
            lastUpdate: now.addingTimeInterval(-2 * 60 * 60)
        )
        let failedJob = Self.makeJob(
            id: 9,
            isActive: false,
            isError: true,
            lastUpdate: now.addingTimeInterval(-2 * 60 * 60)
        )
        var storedCompletedJob = completedJob
        var storedFailedJob = failedJob
        try database.saveDownloadJob(&expiredJob)
        try database.saveDownloadJob(&storedCompletedJob)
        try database.saveDownloadJob(&storedFailedJob)

        let store = TestStore(initialState: UploadFeature.State()) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.date.now = now
        }
        store.timeout = .seconds(5)

        let task = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded) {
            $0.hasLoadedJobs = true
            $0.jobDetails[8] = completedJob
            $0.jobDetails[9] = failedJob
            $0.retiredJobIDs = [7]
        }
        await task.finish()

        XCTAssertEqual(try database.readAllDownloadJobs(), [completedJob, failedJob])
    }

    @MainActor
    func testCheckJobStatusRefreshesOldUnfinishedJobInsteadOfExpiringIt() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let queuedJob = Self.makeJob(id: 7, lastUpdate: now.addingTimeInterval(-25 * 60 * 60))
        var storedJob = queuedJob
        try database.saveDownloadJob(&storedJob)
        let service = try await Self.configuredService()
        Self.stubJobStatus(id: 7, state: "finished", success: 1)

        let store = TestStore(initialState: UploadFeature.State()) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.date.now = now
        }
        store.timeout = .seconds(5)

        let task = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded) {
            $0.hasLoadedJobs = true
            $0.jobDetails[7] = queuedJob
        }

        let refreshedJob = Self.makeJob(
            id: 7,
            title: "Archive Title",
            isActive: false,
            isSuccess: true,
            message: "Done",
            lastUpdate: now
        )
        await store.receive(\.jobStatusUpdated) {
            $0.jobDetails[7] = refreshedJob
        }
        await task.finish()

        XCTAssertEqual(try database.readAllDownloadJobs(), [refreshedJob])
    }

    @MainActor
    func testCheckJobStatusDropsUnfinishedJobNotUpdatedForADayWhenRefreshFails() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let staleJob = Self.makeJob(id: 7, lastUpdate: now.addingTimeInterval(-24 * 60 * 60 - 1))
        var storedJob = staleJob
        try database.saveDownloadJob(&storedJob)
        let service = try await Self.configuredService()
        stub(condition: isHost("localhost") && isPath("/api/minion/7/detail")) { @Sendable _ in
            HTTPStubsResponse(data: Data(), statusCode: 404, headers: nil)
        }

        let store = TestStore(initialState: UploadFeature.State()) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.date.now = now
        }
        store.timeout = .seconds(5)

        let task = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded) {
            $0.hasLoadedJobs = true
            $0.jobDetails[7] = staleJob
        }
        await store.receive(\.jobsLoaded) {
            $0.jobDetails[7] = nil
            $0.retiredJobIDs = [7]
        }
        await task.finish()

        XCTAssertEqual(try database.readAllDownloadJobs(), [])
    }

    @MainActor
    func testCheckJobStatusCanBeCancelledWhilePollingAnActiveJob() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let cachedJob = Self.makeJob(id: 7, lastUpdate: now.addingTimeInterval(-60))
        var storedJob = cachedJob
        try database.saveDownloadJob(&storedJob)
        let service = try await Self.configuredService()
        Self.stubJobStatus(id: 7, state: "active", success: nil)
        let clock = TestClock()

        let store = TestStore(initialState: UploadFeature.State()) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.continuousClock = clock
            $0.date.now = now
        }
        store.timeout = .seconds(5)

        let task = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded) {
            $0.hasLoadedJobs = true
            $0.jobDetails[7] = cachedJob
        }

        let refreshedJob = Self.makeJob(id: 7, lastUpdate: now)
        await store.receive(\.jobStatusUpdated) {
            $0.jobDetails[7] = refreshedJob
        }

        // Checking again replaces the running loop, so the next tick polls once, not twice.
        let secondTask = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded)
        await store.receive(\.jobStatusUpdated)
        await clock.advance(by: .seconds(5))
        await store.receive(\.jobsLoaded)
        await store.receive(\.jobStatusUpdated)
        await task.cancel()
        await secondTask.cancel()
    }

    @MainActor
    func testQueueDownloadQueuesEachPastedLineAndKeepsGoingAfterAFailure() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let service = try await Self.configuredService()
        Self.stubQueueDownload(url: "https://example.com/a", job: 11)
        Self.stubQueueDownload(url: "https://example.com/b", job: nil)
        Self.stubQueueDownload(url: "https://example.com/c", job: 13)
        Self.stubJobStatus(id: 11, state: "active", success: nil)
        Self.stubJobStatus(id: 13, state: "active", success: nil)
        let store = TestStore(initialState: UploadFeature.State()) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.continuousClock = TestClock()
            $0.date.now = now
        }
        store.timeout = .seconds(5)
        store.exhaustivity = .off(showSkippedAssertions: false)

        // Lines are trimmed, blank lines skipped, and one failed URL doesn't stop the rest.
        let pasted = "  https://example.com/a \n\n https://example.com/b\nhttps://example.com/c  \n"
        await store.send(.queueDownload(pasted)) {
            $0.isQueueing = true
        }
        await store.receive(\.queueDownloadFinished) {
            $0.isQueueing = false
        }

        XCTAssertEqual(Set(store.state.jobDetails.keys), [11, 13])
        XCTAssertEqual(Set(try database.readAllDownloadJobs().map(\.id)), [11, 13])
        await store.skipInFlightEffects(strict: false)
    }

    @MainActor
    func testRetryKeepsTheFailedJobWhenItCannotBeQueuedAgain() async throws {
        let (store, database) = try await makeRetryStore()
        Self.stubQueueDownload(url: "https://example.com/archive.zip", job: nil)

        await store.send(.retryDownload(7)) {
            $0.retryingJobIDs = [7]
        }
        await store.receive(\.retryDownloadFinished) {
            $0.retryingJobIDs = []
        }

        XCTAssertNotNil(store.state.jobDetails[7])
        XCTAssertEqual(try database.readAllDownloadJobs().map(\.id), [7])
    }

    @MainActor
    func testRetryReplacesTheFailedJobOnceItIsQueuedAgain() async throws {
        let (store, database) = try await makeRetryStore()
        Self.stubQueueDownload(url: "https://example.com/archive.zip", job: 8)
        Self.stubJobStatus(id: 8, state: "active", success: nil)

        await store.send(.retryDownload(7)) {
            $0.retryingJobIDs = [7]
        }
        await store.receive(\.retryDownloadFinished) {
            $0.retryingJobIDs = []
        }

        XCTAssertNil(store.state.jobDetails[7])
        XCTAssertNotNil(store.state.jobDetails[8])
        XCTAssertTrue(store.state.retiredJobIDs.contains(7))
        XCTAssertEqual(try database.readAllDownloadJobs().map(\.id), [8])
        await store.skipInFlightEffects(strict: false)
    }

    @MainActor
    private func makeRetryStore() async throws -> (TestStoreOf<UploadFeature>, AppDatabase) {
        let database = try AppDatabase(DatabaseQueue())
        var failedJob = Self.makeJob(id: 7, isActive: false, isError: true, message: "Failed", lastUpdate: now)
        try database.saveDownloadJob(&failedJob)
        let service = try await Self.configuredService()
        var state = UploadFeature.State()
        state.jobDetails[7] = failedJob
        let store = TestStore(initialState: state) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.lanraragiService = service
            $0.continuousClock = TestClock()
            $0.date.now = now
        }
        store.timeout = .seconds(5)
        store.exhaustivity = .off(showSkippedAssertions: false)
        return (store, database)
    }

    /// Queues `url` as job `job`, or fails the request when `job` is nil.
    private static func stubQueueDownload(url: String, job: Int?) {
        stub(condition: isHost("localhost")
                && isPath("/api/download_url")
                && isMethodPOST()
                && containsQueryParams(["url": url])
                && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable _ in
            guard let job else {
                return HTTPStubsResponse(data: Data(), statusCode: 500, headers: nil)
            }
            return HTTPStubsResponse(
                jsonObject: ["job": job, "operation": "download_url", "success": 1, "url": url],
                statusCode: 200, headers: ["Content-Type": "application/json"]
            )
        }
    }

    private static func configuredService() async throws -> LANraragiService {
        try await configureTestServer()
    }

    private static func stubJobStatus(id: Int, state: String, success: Int?) {
        let result: String
        if let success {
            result = """
            {
              "success": \(success),
              "url": "https://example.com/archive.zip",
              "title": "Archive Title",
              "message": "Done"
            }
            """
        } else {
            result = "null"
        }
        let body = Data("""
        {
          "id": "\(id)",
          "state": "\(state)",
          "task": "download_url",
          "result": \(result)
        }
        """.utf8)

        stub(condition: isHost("localhost")
                && isPath("/api/minion/\(id)/detail")
                && isMethodGET()) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    private static func makeJob(
        id: Int,
        title: String = "",
        isActive: Bool = true,
        isSuccess: Bool = false,
        isError: Bool = false,
        message: String = "",
        lastUpdate: Date
    ) -> DownloadJob {
        DownloadJob(
            id: id,
            url: "https://example.com/archive.zip",
            title: title,
            isActive: isActive,
            isSuccess: isSuccess,
            isError: isError,
            message: message,
            lastUpdate: lastUpdate
        )
    }
}
