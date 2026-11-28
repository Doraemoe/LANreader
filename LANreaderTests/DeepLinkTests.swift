import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
import UIKit
@testable import LANreader

final class DeepLinkTests: LANreaderTestCase {
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

    /// The Save URL extension builds these links, so every URL it can be handed must come back
    /// unchanged when the app parses the link.
    func testSaveURLExtensionLinksQueueTheSameURLInTheApp() throws {
        let sharedURLs = [
            "https://example.com/g/1",
            "http://example.com/g/1",
            "https://example.com/g/1?page=2&sort=asc#comments",
            "https://example.com/search?q=a%26b%20c&tag=artist:x",
            "https://user:pass@example.com:8443/a+b/c?d=e%2Bf",
            "https://example.com/%E3%83%91%E3%82%B9?name=%E5%80%A4"
        ]
        for sharedURL in sharedURLs {
            let url = try url(sharedURL)
            XCTAssertEqual(DeepLink(url: url.lanReaderAppDeepLink), .download(url), sharedURL)
        }
    }

    @MainActor
    func testAppStateInitializesDestinationForPasscodeAndMissingServer() {
        let suite = "DeepLinkTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        if case .login = makeAppState(defaults: defaults).destination {
            // Expected login screen when no server is configured.
        } else {
            XCTFail("Expected login destination when server URL is missing")
        }

        defaults.set("123456", forKey: SettingsKey.passcode)
        if case .lockScreen = makeAppState(defaults: defaults).destination {
            // Expected lock screen to take precedence on cold start.
        } else {
            XCTFail("Expected lock screen destination when passcode is set")
        }

        defaults.set(TestServer.url, forKey: SettingsKey.lanraragiUrl)
        defaults.removeObject(forKey: SettingsKey.passcode)
        XCTAssertNil(makeAppState(defaults: defaults).destination)
    }

    @MainActor
    func testReadLinkOpensArchiveFromServer() async throws {
        try await configureTestServer()
        stubArchiveMetadata(id: "abc123", statusCode: 200)
        let store = try makeAppTestStore(initialState: makeAppState(selectedTab: .settings))

        await store.send(.openURL(try url("lanreader://read?id=abc123")))
        await store.receive(\.deepLinkArchiveLoaded)
        await store.receive(\.library.openDeepLinkReader)

        let expected = ArchiveItem(
            id: "abc123", name: "Linked archive", extension: "zip", tags: "artist:e auo",
            isNew: false, progress: 7, pagecount: 20, dateAdded: nil
        )
        XCTAssertEqual(store.state.selectedTab, .library)
        XCTAssertNil(store.state.pendingDeepLink)
        XCTAssertEqual(store.state.archiveItems[id: "abc123"], expected)
        guard case let .reader(readerState) = store.state.library.path.first else {
            return XCTFail("Expected reader on library path")
        }
        XCTAssertEqual(readerState.currentArchiveId, "abc123")
        XCTAssertFalse(readerState.cached)
    }

    @MainActor
    func testPreferCachedReadLinkOpensCachedArchiveWithoutServer() async throws {
        try await configureTestServer()
        stub(condition: isHost("localhost") && pathStartsWith("/api/archives/abc123")) { @Sendable _ in
            XCTFail("A cached archive opened with preferCached must not ask the server")
            return HTTPStubsResponse(data: Data(), statusCode: 500, headers: nil)
        }
        let database = try savedCache(id: "abc123")
        let store = try makeAppTestStore(database: database)

        await store.send(.openURL(try url("lanreader://read?id=abc123&preferCached=true")))
        await store.receive(\.deepLinkArchiveLoaded)
        await store.receive(\.library.openDeepLinkReader)

        let cache = try XCTUnwrap(database.readCache("abc123"))
        XCTAssertEqual(store.state.selectedTab, .library)
        XCTAssertNil(store.state.pendingDeepLink)
        guard case let .reader(readerState) = store.state.library.path.first else {
            return XCTFail("Expected cached reader on library path")
        }
        XCTAssertEqual(readerState.currentArchiveId, cache.id)
        XCTAssertTrue(readerState.cached)
    }

    @MainActor
    func testReadLinkIgnoresCacheWithoutPreferCached() async throws {
        try await configureTestServer()
        stubArchiveMetadata(id: "abc123", statusCode: 500)
        let store = try makeAppTestStore(database: savedCache(id: "abc123"))

        await store.send(.openURL(try url("lanreader://read?id=abc123")))
        await store.receive(\.setErrorMessage) {
            $0.errorMessage = String(localized: "error.deeplink.archive")
        }

        XCTAssertNil(store.state.pendingDeepLink)
        XCTAssertTrue(store.state.library.path.isEmpty)
    }

    @MainActor
    func testTankoubonReadLinkAddsUpContainedArchivePages() async throws {
        try await configureTestServer()
        stubTankoubon(id: "TANK_42", pages: ["a": 10, "b": 15])
        let store = try makeAppTestStore()

        await store.send(.openURL(try url("lanreader://read?id=TANK_42")))
        await store.receive(\.deepLinkArchiveLoaded)
        await store.receive(\.library.openDeepLinkReader)

        guard case let .reader(readerState) = store.state.library.path.first,
              let archive = readerState.allArchives[id: "TANK_42"]?.wrappedValue else {
            return XCTFail("Expected a reader route on library path")
        }
        XCTAssertFalse(readerState.cached)
        XCTAssertEqual(archive.name, "Linked tankoubon")
        XCTAssertEqual(archive.pagecount, 25)
        XCTAssertEqual(archive.progress, 3)
    }

    @MainActor
    func testSearchLinkRunsSearchAndRecordsHistory() async throws {
        try await configureTestServer()
        stubSearchResult(query: "artist:e auo", archiveId: "searchHit")
        var initialState = makeAppState(selectedTab: .library)
        initialState.search.path.append(
            .search(SearchFeature.State(keyword: "old"))
        )
        initialState.search.root.archiveList.$lastTagRefresh = Shared(value: Date().timeIntervalSince1970)
        initialState.search.root.archiveList.$searchSort = Shared(value: SearchSort.name.rawValue)
        let store = try makeAppTestStore(initialState: initialState)
        defer { store.state.$archiveItems.withLock { $0 = [] } }

        await store.send(.openURL(try url("lanreader://search?query=artist%3Ae%20auo"))) {
            $0.selectedTab = .search
            $0.pendingDeepLink = nil
        }
        await store.receive(\.search.openDeepLinkSearch) {
            $0.search.path.removeAll()
        }
        await store.receive(\.search.root.recentSearchTapped)
        await store.receive(\.search.root.searchSubmit)
        await store.receive(\.search.root.loadRecentSearches)
        await store.receive(\.search.root.archiveList.reloadFromFirstPage)
        await store.receive(\.search.root.archiveList.populateArchives)

        XCTAssertEqual(store.state.search.root.keyword, "artist:e auo")
        XCTAssertEqual(store.state.search.root.archiveList.filter.filter, "artist:e auo")
        XCTAssertEqual(store.state.search.root.archiveList.archivesToDisplay.ids, ["searchHit"])
        XCTAssertEqual(store.state.search.root.recentSearches, ["artist:e auo"])
        XCTAssertTrue(store.state.search.path.isEmpty)
    }

    @MainActor
    func testDeepLinksCancelInFlightEffectsOnReplacedNavigationStacks() async throws {
        try await configureTestServer()
        stubSearchResult(query: "artist:next", archiveId: "nextHit")
        var initialState = makeAppState()
        initialState.library.path.append(.search(SearchFeature.State()))
        initialState.search.path.append(.search(SearchFeature.State()))
        initialState.search.root.archiveList.$lastTagRefresh = Shared(value: Date().timeIntervalSince1970)
        let librarySearchID = try XCTUnwrap(initialState.library.path.ids.first)
        let searchStackID = try XCTUnwrap(initialState.search.path.ids.first)

        let database = try AppDatabase(DatabaseQueue())
        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.continuousClock = TestClock()
            $0.date.now = Date(timeIntervalSince1970: 1)
            $0.defaultAppStorage = .standard
        }
        store.exhaustivity = .off
        store.timeout = .seconds(5)
        defer { store.state.search.root.archiveList.$lastTagRefresh.withLock { $0 = 0 } }

        await store.send(.library(.path(.element(
            id: librarySearchID, action: .search(.generateSuggestion("artist:pending"))
        ))))
        await store.send(.search(.path(.element(
            id: searchStackID, action: .search(.generateSuggestion("artist:pending"))
        ))))

        let archive = ArchiveItem(
            id: "arc1", name: "Linked", extension: "zip", tags: "",
            isNew: false, progress: 0, pagecount: 10, dateAdded: nil
        )
        await store.send(.deepLinkArchiveLoaded(archive, cached: true))
        await store.receive(\.library.openDeepLinkReader)
        await store.send(.openURL(try url("lanreader://search?query=artist%3Anext")))
        await store.receive(\.search.openDeepLinkSearch)
        await store.receive(\.search.root.archiveList.populateArchives)

        // Both suspended TestClock suggestion effects must be cancelled by StackReducer.
        store.exhaustivity = .on
        await store.finish(timeout: .seconds(2))
    }

    @MainActor
    func testHttpDownloadLinkQueuesUrlUnchangedAndSavesJob() async throws {
        try await configureTestServer()
        stub(condition: isHost("localhost")
                && isPath("/api/download_url")
                && isMethodPOST()
                && containsQueryParams(["url": "http://example.com/g/1"])) { @Sendable _ in
            HTTPStubsResponse(
                data: Data(#"{"job":42,"operation":"download_url","success":1,"url":"http://example.com/g/1"}"#.utf8),
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }
        let database = try AppDatabase(DatabaseQueue())
        let store = try makeAppTestStore(database: database)

        await store.send(.openURL(try url("lanreader://download?url=http%3A%2F%2Fexample.com%2Fg%2F1")))
        await store.receive(\.queueUrlDownload)
        await store.receive(\.setSuccessMessage)

        let jobs = try database.readAllDownloadJobs()
        XCTAssertEqual(jobs.map(\.id), [42])
        XCTAssertEqual(jobs.first?.url, "http://example.com/g/1")
        XCTAssertEqual(jobs.first?.isActive, true)
    }

    @MainActor
    func testTabBarOpensReaderOnLibraryTabAndSearchOnSearchTab() async throws {
        try await configureTestServer()
        stubEmptyArchiveFiles(id: "abc123")
        stubSearchResult(query: "artist:e auo", archiveId: "searchHit")
        let database = try makeDeepLinkThumbnailDatabase(archiveIds: ["searchHit"])
        try await withDependencies {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1)
            $0.defaultAppStorage = .standard
        } operation: {
            let initialState = AppFeature.State()
            initialState.search.root.archiveList.$lastTagRefresh.withLock { $0 = Date().timeIntervalSince1970 }
            let store = Store(initialState: initialState) { AppFeature() }
            defer {
                store.state.$archiveItems.withLock { $0 = [] }
                store.state.search.root.archiveList.$lastTagRefresh.withLock { $0 = 0 }
            }
            let tabs = UITabViewController(store: store)
            tabs.loadViewIfNeeded()
            let libraryNav = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
            libraryNav.loadViewIfNeeded()
            libraryNav.topViewController?.loadViewIfNeeded()
            tabs.selectedIndex = 3
            tabs.tabBarController(tabs, didSelect: try XCTUnwrap(tabs.viewControllers?[3]))
            XCTAssertEqual(store.selectedTab, .settings)

            let archive = ArchiveItem(
                id: "abc123", name: "Linked archive", extension: "zip", tags: "",
                isNew: false, progress: 7, pagecount: 20, dateAdded: nil
            )
            withUITransaction(\.uiKit.disablesAnimations, true) {
                _ = store.send(.deepLinkArchiveLoaded(archive, cached: false))
            }
            await waitUntil {
                store.pendingDeepLink == nil && libraryNav.topViewController is UIArchiveReaderController
            }

            XCTAssertEqual(store.selectedTab, .library)
            XCTAssertEqual(tabs.selectedIndex, 0)
            XCTAssertTrue(libraryNav.topViewController is UIArchiveReaderController)
            XCTAssertEqual(store.library.path.count, 1)
            XCTAssertNil(store.pendingDeepLink)

            store.send(.openURL(try url("lanreader://search?query=artist%3Ae%20auo")))
            await waitUntil {
                store.pendingDeepLink == nil
                    && !store.search.root.archiveList.loading
                    && store.search.root.archiveList.archivesToDisplay.ids == ["searchHit"]
            }

            XCTAssertEqual(store.selectedTab, .search)
            XCTAssertEqual(tabs.selectedIndex, 2)
            XCTAssertNil(store.pendingDeepLink)
            XCTAssertEqual(store.search.root.archiveList.archivesToDisplay.ids, ["searchHit"])
        }
    }

    @MainActor
    func testSearchDeepLinkWaitsForLockScreenAndLoadsOnColdStart() async throws {
        try await configureTestServer()
        UserDefaults.standard.set("123456", forKey: SettingsKey.passcode)
        stubSearchResult(query: "artist:cold", archiveId: "coldHit")
        let database = try makeDeepLinkThumbnailDatabase(archiveIds: ["coldHit"])
        try await withDependencies {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1)
            $0.defaultAppStorage = .standard
        } operation: {
            var initialState = AppFeature.State()
            initialState.search.path.append(.search(SearchFeature.State(keyword: "old")))
            initialState.search.root.archiveList.$lastTagRefresh.withLock { $0 = Date().timeIntervalSince1970 }
            let store = Store(initialState: initialState) { AppFeature() }
            defer {
                store.state.$archiveItems.withLock { $0 = [] }
                store.state.search.root.archiveList.$lastTagRefresh.withLock { $0 = 0 }
            }
            if case .lockScreen = store.destination {
                // Expected lock screen initialized before view appear.
            } else {
                XCTFail("Expected lock screen destination on cold start")
            }
            let tabs = UITabViewController(store: store)
            tabs.loadViewIfNeeded()

            store.send(.openURL(try url("lanreader://search?query=artist%3Acold")))
            await Task.yield()

            XCTAssertEqual(store.pendingDeepLink, .search(query: "artist:cold"))
            XCTAssertEqual(store.selectedTab, .library)
            XCTAssertEqual(tabs.selectedIndex, 0)
            XCTAssertEqual(store.search.path.count, 1)
            XCTAssertEqual(try database.recentSearches(), [])
            XCTAssertTrue(store.search.root.archiveList.archivesToDisplay.isEmpty)

            store.send(.destination(.dismiss))
            await waitUntil {
                store.pendingDeepLink == nil
                    && !store.search.root.archiveList.loading
                    && store.search.root.archiveList.archivesToDisplay.ids == ["coldHit"]
            }

            XCTAssertEqual(store.selectedTab, .search)
            XCTAssertEqual(tabs.selectedIndex, 2)
            XCTAssertTrue(store.search.path.isEmpty)
            XCTAssertEqual(store.search.root.keyword, "artist:cold")
            XCTAssertEqual(try database.recentSearches(), ["artist:cold"])
            XCTAssertEqual(store.search.root.archiveList.archivesToDisplay.ids, ["coldHit"])
            XCTAssertEqual(try searchTabSearchBar(in: tabs).text, "artist:cold")
        }
    }

    @MainActor
    func testReaderDeepLinkWaitsForLockScreenAndReplacesExistingLibraryPath() async throws {
        try await configureTestServer()
        UserDefaults.standard.set("123456", forKey: SettingsKey.passcode)
        stubEmptyArchiveFiles(id: "abc123")
        let database = try AppDatabase(DatabaseQueue())
        try await withDependencies {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1)
            $0.defaultAppStorage = .standard
        } operation: {
            var initialState = AppFeature.State(selectedTab: .search)
            initialState.library.path.append(.cache(CacheFeature.State()))
            let store = Store(initialState: initialState) { AppFeature() }
            defer { store.state.$archiveItems.withLock { $0 = [] } }
            if case .lockScreen = store.destination {
                // Expected lock screen initialized before view appear.
            } else {
                XCTFail("Expected lock screen destination on cold start")
            }
            let tabs = UITabViewController(store: store)
            tabs.loadViewIfNeeded()
            let libraryNav = try XCTUnwrap(tabs.viewControllers?.first as? UINavigationController)
            libraryNav.loadViewIfNeeded()
            libraryNav.topViewController?.loadViewIfNeeded()
            XCTAssertEqual(tabs.selectedIndex, 2)

            let archive = ArchiveItem(
                id: "abc123", name: "Linked archive", extension: "zip", tags: "",
                isNew: false, progress: 7, pagecount: 20, dateAdded: nil
            )
            store.send(.deepLinkArchiveLoaded(archive, cached: false))
            await Task.yield()

            XCTAssertEqual(store.pendingDeepLink, .reader(archive, cached: false))
            XCTAssertEqual(store.selectedTab, .search)
            XCTAssertEqual(tabs.selectedIndex, 2)
            if case .cache = store.library.path.first {
                // Expected to keep existing path untouched until unlocked.
            } else {
                XCTFail("Expected cache screen to stay on stack while locked")
            }

            withUITransaction(\.uiKit.disablesAnimations, true) {
                _ = store.send(.destination(.dismiss))
            }
            await waitUntil {
                store.pendingDeepLink == nil && libraryNav.topViewController is UIArchiveReaderController
            }

            XCTAssertEqual(store.selectedTab, .library)
            XCTAssertEqual(tabs.selectedIndex, 0)
            XCTAssertEqual(libraryNav.viewControllers.count, 2)
            XCTAssertTrue(libraryNav.topViewController is UIArchiveReaderController)
            XCTAssertEqual(store.library.path.count, 1)
        }
    }

    @MainActor
    func testSearchControllerSyncsKeywordAndDismissesSuggestionsOnExternalSearch() async throws {
        try await configureTestServer()
        stubSearchResult(query: "artist:deep", archiveId: "deepHit")
        let database = try makeDeepLinkThumbnailDatabase(archiveIds: ["deepHit"])
        var popularTag = TagItem(tag: "female:b", count: 10)
        try database.saveTag(tagItem: &popularTag)
        let initialState = SearchFeature.State()
        initialState.archiveList.$lastTagRefresh = Shared(value: Date().timeIntervalSince1970)
        initialState.archiveList.$searchSort = Shared(value: SearchSort.name.rawValue)
        let store = withDependencies {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 10)
        } operation: {
            Store(initialState: initialState) { SearchFeature() }
        }
        defer { store.state.archiveList.$archiveItems.withLock { $0 = [] } }
        let controller = UISearchViewV2Controller(store: store)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.loadViewIfNeeded()
        controller.loadViewIfNeeded()
        await Task.yield()

        let searchBar = try XCTUnwrap(
            controller.navigationItem.searchController?.searchBar
                ?? controller.view.firstSubview(of: UISearchBar.self)
        )
        let suggestions = try XCTUnwrap(controller.view.firstSubview(of: UITableView.self))
        controller.searchBarTextDidBeginEditing(searchBar)
        XCTAssertFalse(suggestions.isHidden)

        store.send(.recentSearchTapped("artist:deep"))
        await waitUntil {
            !store.archiveList.loading
                && store.archiveList.archivesToDisplay.ids == ["deepHit"]
                && searchBar.text == "artist:deep"
        }

        XCTAssertEqual(searchBar.text, "artist:deep")
        XCTAssertTrue(suggestions.isHidden)
        XCTAssertEqual(store.archiveList.archivesToDisplay.ids, ["deepHit"])
    }
}

@MainActor
private func searchTabSearchBar(in tabs: UITabViewController) throws -> UISearchBar {
    let searchNav = try XCTUnwrap(tabs.viewControllers?[TabName.search.tabIndex] as? UINavigationController)
    let searchController = try XCTUnwrap(searchNav.topViewController as? UISearchViewV2Controller)
    searchController.loadViewIfNeeded()
    return try XCTUnwrap(
        searchController.navigationItem.searchController?.searchBar
            ?? searchController.view.firstSubview(of: UISearchBar.self)
    )
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
private func makeAppState(
    selectedTab: TabName = .library,
    destination: AppFeature.Destination.State? = nil,
    defaults: UserDefaults = .standard
) -> AppFeature.State {
    withDependencies {
        $0.defaultAppStorage = defaults
    } operation: {
        AppFeature.State(selectedTab: selectedTab, destination: destination)
    }
}

@MainActor
private func makeAppTestStore(
    initialState: AppFeature.State? = nil,
    database: AppDatabase? = nil
) throws -> TestStoreOf<AppFeature> {
    let database = try database ?? AppDatabase(DatabaseQueue())
    let store = TestStore(initialState: initialState ?? makeAppState()) {
        AppFeature()
    } withDependencies: {
        $0.appDatabase = database
        $0.date.now = Date(timeIntervalSince1970: 1)
        $0.defaultAppStorage = .standard
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

private func stubEmptyArchiveFiles(id: String) {
    stub(condition: isHost("localhost") && isPath("/api/archives/\(id)/files") && isMethodGET()) { @Sendable _ in
        HTTPStubsResponse(jsonObject: ["pages": []], statusCode: 200, headers: ["Content-Type": "application/json"])
    }
}

private func stubSearchResult(query: String, archiveId: String) {
    stub(condition: isHost("localhost")
            && isPath("/api/search")
            && isMethodGET()
            && containsQueryParams(["filter": query])) { @Sendable _ in
        HTTPStubsResponse(jsonObject: [
            "data": [[
                "arcid": archiveId, "extension": "zip", "isnew": "false", "tags": query,
                "title": "Matched archive", "pagecount": 10, "progress": 0
            ]],
            "recordsFiltered": 1,
            "recordsTotal": 1
        ], statusCode: 200, headers: ["Content-Type": "application/json"])
    }
}

@MainActor
private func makeDeepLinkThumbnailDatabase(archiveIds: [String]) throws -> AppDatabase {
    let database = try AppDatabase(DatabaseQueue())
    let thumbnailData = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { _ in }
    for id in archiveIds {
        var thumbnail = ArchiveThumbnail(id: id, thumbnail: thumbnailData, lastUpdate: Date())
        try database.saveArchiveThumbnail(&thumbnail)
    }
    return database
}
