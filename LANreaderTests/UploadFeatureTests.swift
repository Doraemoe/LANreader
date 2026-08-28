import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class UploadFeatureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    override func tearDownWithError() throws {
        UserDefaults.resetStandardUserDefaults()
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
    func testCheckJobStatusRemovesExpiredJobsWithoutRefreshingThem() async throws {
        let database = try AppDatabase(DatabaseQueue())
        var expiredJob = Self.makeJob(id: 7, lastUpdate: now.addingTimeInterval(-3601))
        let completedJob = Self.makeJob(
            id: 8,
            isActive: false,
            isSuccess: true,
            lastUpdate: now.addingTimeInterval(-60)
        )
        var storedCompletedJob = completedJob
        try database.saveDownloadJob(&expiredJob)
        try database.saveDownloadJob(&storedCompletedJob)

        let store = TestStore(initialState: UploadFeature.State()) {
            UploadFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.date.now = now
        }

        let task = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded) {
            $0.hasLoadedJobs = true
            $0.jobDetails[8] = completedJob
            $0.retiredJobIDs = [7]
        }
        await task.finish()

        XCTAssertEqual(try database.readAllDownloadJobs(), [completedJob])
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

        let task = await store.send(.checkJobStatus)
        await store.receive(\.jobsLoaded) {
            $0.hasLoadedJobs = true
            $0.jobDetails[7] = cachedJob
        }

        let refreshedJob = Self.makeJob(id: 7, lastUpdate: now)
        await store.receive(\.jobStatusUpdated) {
            $0.jobDetails[7] = refreshedJob
        }
        await task.cancel()
    }

    private static func configuredService() async throws -> LANraragiService {
        let body = Data("""
        {
          "archives_per_page": 100,
          "debug_mode": false,
          "has_password": true,
          "motd": "Welcome",
          "name": "LANraragi",
          "nofun_mode": false,
          "server_tracks_progress": true,
          "version": "0.9.30",
          "version_name": "Law"
        }
        """.utf8)
        stub(condition: isHost("localhost")
                && isPath("/api/info")
                && isMethodGET()) { _ in
            HTTPStubsResponse(
                data: body,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }

        let service = LANraragiService.shared
        _ = try await service.verifyClient(url: "https://localhost", apiKey: "apiKey")
        return service
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
