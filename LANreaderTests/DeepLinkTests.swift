import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
import UIKit
@testable import LANreader

final class DeepLinkTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
        super.tearDown()
    }

    func testParsesReadAndSearchLinks() throws {
        XCTAssertEqual(
            DeepLink(url: try url("lanreader://read?id=abc123")),
            .read(archiveId: "abc123", preferCached: false)
        )
        XCTAssertEqual(
            DeepLink(url: try url("LANREADER://Read?id=TANK_42&preferCached=TRUE")),
            .read(archiveId: "TANK_42", preferCached: true)
        )
        XCTAssertEqual(
            DeepLink(url: try url("lanreader://read?id=abc123&preferCached=false")),
            .read(archiveId: "abc123", preferCached: false)
        )
        XCTAssertEqual(
            DeepLink(url: try url("lanreader://search?query=artist%3Ae%20auo%24%2C")),
            .search(query: "artist:e auo$,")
        )
    }

    func testRejectsIncompleteOrUnsafeLinks() throws {
        XCTAssertNil(DeepLink(url: try url("lanreader://read")))
        XCTAssertNil(DeepLink(url: try url("lanreader://read?id=")))
        XCTAssertNil(DeepLink(url: try url("lanreader://read?id=..%2Fapi%2Fdatabase")))
        XCTAssertNil(DeepLink(url: try url("lanreader://search?query=%20")))
        XCTAssertNil(DeepLink(url: try url("https://read?id=abc123")))
        XCTAssertNil(DeepLink(url: try url("lanreader://unknown?id=abc123")))
        XCTAssertNil(DeepLink(url: try url("lanreader://example.com/g/1")))
        XCTAssertNil(DeepLink(url: try url("lanreader://download")))
        XCTAssertNil(DeepLink(url: try url("lanreader://download?url=file%3A%2F%2F%2Fetc%2Fhosts")))
    }

    func testParsesDownloadLinks() throws {
        XCTAssertEqual(
            DeepLink(url: try url("lanreader://download?url=https%3A%2F%2Fexample.com%2Fg%2F1%3Fpage%3D2")),
            .download(try url("https://example.com/g/1?page=2"))
        )
        XCTAssertEqual(
            DeepLink(url: try url("lanreader://download?url=http%3A%2F%2Fexample.com%2Fg%2F1")),
            .download(try url("http://example.com/g/1"))
        )
    }

    @MainActor
    func testReadLinkOpensArchiveFromServer() async throws {
        try await configureArchiveListTestClient()
        stubArchiveMetadata(id: "abc123", statusCode: 200)
        let store = try makeAppTestStore()

        await store.send(.openURL(try url("lanreader://read?id=abc123")))
        await store.receive(\.deepLinkArchiveLoaded)

        let expected = ArchiveItem(
            id: "abc123", name: "Linked archive", extension: "zip", tags: "artist:e auo",
            isNew: false, progress: 7, pagecount: 20, dateAdded: nil
        )
        XCTAssertEqual(store.state.pendingDeepLink, .reader(expected, cached: false))
        XCTAssertEqual(store.state.archiveItems[id: "abc123"], expected)
    }

    @MainActor
    func testPreferCachedReadLinkOpensCachedArchiveWithoutServer() async throws {
        try await configureArchiveListTestClient()
        stubArchiveMetadata(id: "abc123", statusCode: 200)
        let database = try savedCache(id: "abc123")
        let store = try makeAppTestStore(database: database)

        await store.send(.openURL(try url("lanreader://read?id=abc123&preferCached=true")))
        await store.receive(\.deepLinkArchiveLoaded)

        let cache = try XCTUnwrap(database.readCache("abc123"))
        XCTAssertEqual(store.state.pendingDeepLink, .reader(cache.toArchiveItem(), cached: true))
    }

    @MainActor
    func testReadLinkIgnoresCacheWithoutPreferCached() async throws {
        try await configureArchiveListTestClient()
        stubArchiveMetadata(id: "abc123", statusCode: 500)
        let store = try makeAppTestStore(database: savedCache(id: "abc123"))

        await store.send(.openURL(try url("lanreader://read?id=abc123")))
        await store.receive(\.setErrorMessage) {
            $0.errorMessage = String(localized: "error.deeplink.archive")
        }

        XCTAssertNil(store.state.pendingDeepLink)
    }

    @MainActor
    func testReadLinkShowsErrorForUnknownArchive() async throws {
        try await configureArchiveListTestClient()
        stubArchiveMetadata(id: "missing", statusCode: 404)
        let store = try makeAppTestStore()

        await store.send(.openURL(try url("lanreader://read?id=missing")))
        await store.receive(\.setErrorMessage) {
            $0.errorMessage = String(localized: "error.deeplink.archive")
        }

        XCTAssertNil(store.state.pendingDeepLink)
    }

    @MainActor
    func testTankoubonReadLinkAddsUpContainedArchivePages() async throws {
        try await configureArchiveListTestClient()
        stubTankoubon(id: "TANK_42", pages: ["a": 10, "b": 15])
        let store = try makeAppTestStore()

        await store.send(.openURL(try url("lanreader://read?id=TANK_42")))
        await store.receive(\.deepLinkArchiveLoaded)

        guard case let .reader(archive, cached) = store.state.pendingDeepLink else {
            return XCTFail("Expected a reader route")
        }
        XCTAssertFalse(cached)
        XCTAssertEqual(archive.name, "Linked tankoubon")
        XCTAssertEqual(archive.pagecount, 25)
        XCTAssertEqual(archive.progress, 3)
    }

    @MainActor
    func testSearchLinkRunsSearchAndRecordsHistory() async throws {
        let store = try makeAppTestStore()

        await store.send(.openURL(try url("lanreader://search?query=artist%3Ae%20auo"))) {
            $0.pendingDeepLink = .search(query: "artist:e auo")
        }
        await store.receive(\.search.recentSearchTapped)
        await store.receive(\.search.searchSubmit)
        await store.receive(\.search.loadRecentSearches)

        XCTAssertEqual(store.state.search.keyword, "artist:e auo")
        XCTAssertEqual(store.state.search.archiveList.filter.filter, "artist:e auo")
        XCTAssertEqual(store.state.search.recentSearches, ["artist:e auo"])
    }

    @MainActor
    func testDownloadLinkQueuesDownload() async throws {
        let store = try makeAppTestStore()

        await store.send(.openURL(try url("lanreader://download?url=https%3A%2F%2Fexample.com%2Fg%2F1")))
        await store.receive(\.queueUrlDownload, try url("https://example.com/g/1"))
    }

    @MainActor
    func testTabBarOpensReaderOnLibraryTabAndSearchOnSearchTab() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = withDependencies {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1)
        } operation: {
            Store(initialState: AppFeature.State()) { AppFeature() }
        }
        let tabs = UITabViewController(store: store)
        tabs.loadViewIfNeeded()
        tabs.selectedIndex = 3

        let archive = ArchiveItem(
            id: "abc123", name: "Linked archive", extension: "zip", tags: "",
            isNew: false, progress: 7, pagecount: 20, dateAdded: nil
        )
        store.send(.deepLinkArchiveLoaded(archive, cached: false))
        await waitUntil { store.pendingDeepLink == nil }

        XCTAssertEqual(tabs.selectedIndex, 0)
        let libraryNav = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
        XCTAssertTrue(libraryNav.topViewController is UIArchiveReaderController)
        XCTAssertNil(store.pendingDeepLink)

        store.send(.openURL(try url("lanreader://search?query=artist%3Ae%20auo")))
        await waitUntil { store.pendingDeepLink == nil }

        XCTAssertEqual(tabs.selectedIndex, 2)
        XCTAssertNil(store.pendingDeepLink)
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private func savedCache(id: String) throws -> AppDatabase {
    let database = try AppDatabase(DatabaseQueue())
    var cache = ArchiveCache(
        id: id, title: "Cached archive", tags: "", thumbnail: nil,
        cached: true, totalPages: 12, toc: nil, lastUpdate: Date(), progress: 4
    )
    try database.saveCache(&cache)
    return database
}

private func url(_ string: String) throws -> URL {
    try XCTUnwrap(URL(string: string))
}

@MainActor
private func makeAppTestStore(database: AppDatabase? = nil) throws -> TestStoreOf<AppFeature> {
    let database = try database ?? AppDatabase(DatabaseQueue())
    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.appDatabase = database
        $0.date.now = Date(timeIntervalSince1970: 1)
    }
    store.exhaustivity = .off
    store.timeout = .seconds(5)
    return store
}

private func stubTankoubon(id: String, pages: KeyValuePairs<String, Int>) {
    let archives = pages.map { archiveId, count in
        [
            "arcid": archiveId, "extension": "zip", "isnew": "false",
            "title": archiveId, "pagecount": count, "progress": 0
        ]
    }
    let body = try? JSONSerialization.data(withJSONObject: [
        "result": [
            "id": id, "name": "Linked tankoubon", "summary": "", "tags": "",
            "progress": 3, "archives": pages.map(\.key), "full_data": archives
        ] as [String: Any],
        "total": pages.count, "filtered": pages.count
    ])
    stub(condition: isHost("localhost") && isPath("/api/tankoubons/\(id)/full")) { @Sendable _ in
        HTTPStubsResponse(data: body ?? Data(), statusCode: 200, headers: ["Content-Type": "application/json"])
    }
}

private func stubArchiveMetadata(id: String, statusCode: Int32) {
    stub(condition: isHost("localhost") && isPath("/api/archives/\(id)/metadata") && isMethodGET()) { @Sendable _ in
        guard statusCode == 200 else {
            return HTTPStubsResponse(data: Data(), statusCode: statusCode, headers: nil)
        }
        return HTTPStubsResponse(jsonObject: [
            "arcid": id, "extension": "zip", "isnew": "false", "tags": "artist:e auo",
            "title": "Linked archive", "pagecount": 20, "progress": 7
        ], statusCode: 200, headers: ["Content-Type": "application/json"])
    }
}
