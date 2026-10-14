import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class TagRefreshFeatureTests: XCTestCase {
    override func tearDownWithError() throws {
        UserDefaults.resetStandardUserDefaults()
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    func testRefreshReplacesSuggestionsAndMarksSuccessAfterCommit() async throws {
        try await configureArchiveListTestClient()
        let database = try makeTagRefreshDatabase()
        let store = makeTagRefreshStore(database: database)
        let lastRefresh = store.state.$lastTagRefresh
        stubTagRefresh {
            XCTAssertEqual(lastRefresh.wrappedValue, 1)
        }
        let startedAt = Date().timeIntervalSince1970

        await store.send(.load)
        await store.receive(.tagsRefreshed)
        await store.finish()

        let tags = try database.popularTag()
        XCTAssertEqual(tags.map(\.tag), ["artbook", "artist:blocked"])
        XCTAssertEqual(tags.map(\.count), [5, 1])
        XCTAssertGreaterThanOrEqual(store.state.lastTagRefresh, startedAt)
    }

    @MainActor
    func testFailedInsertRollsBackSuggestionsAndAllowsNextLoadToRetry() async throws {
        try await configureArchiveListTestClient()
        stubTagRefresh()
        let writer = try DatabaseQueue()
        let database = try makeTagRefreshDatabase(writer: writer)
        try await writer.write { database in
            try database.execute(sql: """
                CREATE TEMP TRIGGER fail_tag_insert BEFORE INSERT ON tag
                WHEN NEW.tag = 'artist:blocked'
                BEGIN SELECT RAISE(ABORT, 'test insert failure'); END
                """)
        }
        let store = makeTagRefreshStore(database: database)

        await store.send(.load)
        await store.receive(.populateArchives([], 0, false))
        await store.finish()

        let tags = try database.popularTag()
        XCTAssertEqual(tags.map(\.tag), ["artist:original"])
        XCTAssertEqual(tags.map(\.count), [10])
        XCTAssertEqual(store.state.lastTagRefresh, 1)

        try await writer.write { try $0.execute(sql: "DROP TRIGGER fail_tag_insert") }
        await store.send(.load)
        await store.receive(.tagsRefreshed)
        await store.finish()

        XCTAssertEqual(try database.popularTag().map(\.tag), ["artbook", "artist:blocked"])
        XCTAssertGreaterThan(store.state.lastTagRefresh, 1)
    }

    @MainActor
    func testRequestFailureKeepsSuggestionsAndTimestamp() async throws {
        try await configureArchiveListTestClient()
        stubTagRefresh(statusCode: 500)
        let database = try makeTagRefreshDatabase()
        let store = makeTagRefreshStore(database: database)

        await store.send(.load)
        await store.receive(.populateArchives([], 0, false))
        await store.finish()

        XCTAssertEqual(try database.popularTag().map(\.tag), ["artist:original"])
        XCTAssertEqual(store.state.lastTagRefresh, 1)
    }

    @MainActor
    func testRecentRefreshDoesNotRequestStats() async throws {
        try await configureArchiveListTestClient()
        stubTagRefresh()
        stub(condition: isPath("/api/database/stats")) { @Sendable _ in
            XCTFail("A recent tag refresh must not request stats")
            return HTTPStubsResponse(error: URLError(.notConnectedToInternet))
        }
        let database = try makeTagRefreshDatabase()
        let timestamp = Date().timeIntervalSince1970
        let store = makeTagRefreshStore(database: database, lastRefresh: timestamp)

        await store.send(.load)
        await store.receive(.populateArchives([], 0, false))
        await store.finish()

        XCTAssertEqual(try database.popularTag().map(\.tag), ["artist:original"])
        XCTAssertEqual(store.state.lastTagRefresh, timestamp)
    }
}

@MainActor
private func makeTagRefreshStore(database: AppDatabase, lastRefresh: Double = 1) -> TestStoreOf<ArchiveListFeature> {
    let state = makePaginatedArchiveListState()
    state.$lastTagRefresh = Shared(value: lastRefresh)
    let store = TestStore(initialState: state) { ArchiveListFeature() } withDependencies: {
        $0.appDatabase = database
    }
    store.exhaustivity = .off
    store.timeout = .seconds(5)
    return store
}

private func makeTagRefreshDatabase(writer: DatabaseQueue? = nil) throws -> AppDatabase {
    let database = try AppDatabase(writer ?? DatabaseQueue())
    var tag = TagItem(tag: "artist:original", count: 10)
    try database.saveTag(tagItem: &tag)
    return database
}

private func stubTagRefresh(statusCode: Int32 = 200, onRequest: @escaping @Sendable () -> Void = {}) {
    stub(condition: isHost("localhost") && isPath("/api/database/stats")) { @Sendable request in
        onRequest()
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer YXBpS2V5")
        return HTTPStubsResponse(
            data: Data("""
            [
              {"namespace":"","text":"artbook","weight":"5"},
              {"namespace":"artist","text":"blocked","weight":"invalid"},
              {"namespace":"date_added","text":"123","weight":"1"},
              {"namespace":"source","text":"example","weight":"1"}
            ]
            """.utf8),
            statusCode: statusCode, headers: ["Content-Type": "application/json"]
        )
    }
    stub(condition: isHost("localhost") && isPath("/api/search")) { @Sendable _ in
        HTTPStubsResponse(
            data: Data(#"{"data":[],"recordsFiltered":0,"recordsTotal":0}"#.utf8),
            statusCode: 200, headers: ["Content-Type": "application/json"]
        )
    }
}
