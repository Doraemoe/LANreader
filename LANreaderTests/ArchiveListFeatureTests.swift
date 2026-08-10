import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class ArchiveListFeatureTests: XCTestCase {
    override func tearDownWithError() throws {
        UserDefaults.resetStandardUserDefaults()
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    func testSearchTabDoesNotLoadWithoutSearchFilter() async {
        let archive = ArchiveItem(
            id: "existing",
            name: "Existing",
            extension: "zip",
            tags: "",
            isNew: false,
            progress: 0,
            pagecount: 10,
            dateAdded: nil
        )
        var initialState = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .search
        )
        initialState.archives = [GridFeature.State(archive: Shared(value: archive))]
        initialState.archivesToDisplay = initialState.archives
        initialState.total = 1

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }

        await store.send(.load(true)) {
            $0.archives = []
            $0.archivesToDisplay = []
            $0.total = 0
        }
    }

    func testLibraryTabCanLoadWithoutSearchFilter() {
        let state = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            currentTab: .library
        )

        XCTAssertTrue(state.canLoadArchives)
    }

    @MainActor
    func testPageZeroResponseDefinesServerPageSize() async {
        let store = TestStore(initialState: makePaginatedState()) {
            ArchiveListFeature()
        }

        await store.send(.populateArchives(makeArchives(count: 100), 250, false)) {
            $0.archives = expectedGridStates(in: &$0, count: 100)
            $0.archivesToDisplay = $0.archives
            $0.serverPageSize = 100
            $0.total = 250
            $0.loading = false
            $0.showLoading = false
        }

        XCTAssertEqual(store.state.pageCount, 3)
    }

    @MainActor
    func testShortFinalPageDoesNotShrinkServerPageSize() async {
        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250
        initialState.currentPage = 2

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }

        // The last page returns fewer records; the discovered size must survive it.
        await store.send(.populateArchives(makeArchives(count: 50), 250, false)) {
            $0.archives = expectedGridStates(in: &$0, count: 50)
            $0.archivesToDisplay = $0.archives
            $0.loading = false
            $0.showLoading = false
        }

        XCTAssertEqual(store.state.serverPageSize, 100)
        XCTAssertEqual(store.state.pageCount, 3)
    }

    @MainActor
    func testGoToPageIsIgnoredWhilePaginationIsDisabled() async {
        var initialState = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .library
        )
        initialState.$paginateArchiveList = Shared(value: false)
        initialState.serverPageSize = 100
        initialState.total = 250

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }

        await store.send(.goToPage(2))
    }

    @MainActor
    func testGoToPageIsIgnoredForRandomSort() async {
        var initialState = makePaginatedState()
        initialState.$searchSort = Shared(value: SearchSort.random.rawValue)
        initialState.serverPageSize = 100
        initialState.total = 250

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }

        XCTAssertFalse(store.state.paginationActive)
        await store.send(.goToPage(2))
    }

    @MainActor
    func testGoToPageRequestsMatchingServerOffset() async throws {
        try await configureVerifiedClient()
        stubSearchExpectingStart("200", recordsFiltered: 250)

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)

        await store.send(.goToPage(2)) {
            $0.loading = true
            $0.showLoading = true
            $0.pendingPage = 2
        }
        // Only a request with start=200 is stubbed, so reaching populateArchives proves the offset.
        await store.receive(.populateArchives([], 250, false)) {
            $0.currentPage = 2
            $0.pendingPage = nil
            $0.total = 250
            $0.loading = false
            $0.showLoading = false
        }
    }

    @MainActor
    func testGoToPageClampsBeyondLastPage() async throws {
        try await configureVerifiedClient()
        stubSearchExpectingStart("200", recordsFiltered: 250)

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)

        await store.send(.goToPage(99)) {
            $0.loading = true
            $0.showLoading = true
            $0.pendingPage = 2
        }
        await store.receive(.populateArchives([], 250, false)) {
            $0.currentPage = 2
            $0.pendingPage = nil
            $0.total = 250
            $0.loading = false
            $0.showLoading = false
        }
    }

    @MainActor
    func testFailedPageRequestKeepsCurrentPageAndArchives() async throws {
        try await configureVerifiedClient()
        stubFailedSearchExpectingStart("200")

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250
        initialState.archives = expectedGridStates(in: &initialState, count: 1)
        initialState.archivesToDisplay = initialState.archives

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)
        store.exhaustivity = .off

        await store.send(.goToPage(2)) {
            $0.loading = true
            $0.showLoading = true
            $0.pendingPage = 2
        }
        await store.receive(\.setErrorMessage)

        XCTAssertEqual(store.state.currentPage, 0)
        XCTAssertNil(store.state.pendingPage)
        XCTAssertEqual(store.state.archives.map(\.id), ["archive-0"])
    }

    @MainActor
    func testLoadKeepsCurrentPageInPaginationMode() async throws {
        try await configureVerifiedClient()
        stubSearchExpectingStart("200", recordsFiltered: 250)

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250
        initialState.currentPage = 2

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)
        // populateTags stamps a shared timestamp that is irrelevant here.
        store.exhaustivity = .off

        await store.send(.load(true)) {
            $0.loading = true
            $0.showLoading = true
        }
        // Only start=200 is stubbed, so reaching populateArchives proves the page was kept.
        await store.receive(.populateArchives([], 250, false)) {
            $0.total = 250
            $0.loading = false
            $0.showLoading = false
        }
        XCTAssertEqual(store.state.currentPage, 2)
    }

    @MainActor
    func testReloadFromFirstPageRestartsWhileAnotherRequestIsLoading() async throws {
        try await configureVerifiedClient()
        stubSearchExpectingStart("0", recordsFiltered: 250)

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250
        initialState.currentPage = 2
        initialState.pendingPage = 2
        initialState.loading = true
        initialState.showLoading = true
        initialState.archives = expectedGridStates(in: &initialState, count: 1)
        initialState.archivesToDisplay = initialState.archives

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)
        // populateTags stamps a shared timestamp that is irrelevant here.
        store.exhaustivity = .off

        await store.send(.reloadFromFirstPage) {
            $0.archives = []
            $0.archivesToDisplay = []
            $0.currentPage = 0
            $0.pendingPage = nil
        }
        await store.receive(.populateArchives([], 250, false))

        XCTAssertEqual(store.state.currentPage, 0)
        XCTAssertFalse(store.state.loading)
    }

    @MainActor
    func testResetArchivesSendsLoadBackToFirstPage() async throws {
        try await configureVerifiedClient()
        stubSearchExpectingStart("0", recordsFiltered: 250)

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250
        initialState.currentPage = 2

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)
        store.exhaustivity = .off

        await store.send(.resetArchives) {
            $0.currentPage = 0
        }
        await store.send(.load(true)) {
            $0.loading = true
            $0.showLoading = true
        }
        await store.receive(.populateArchives([], 250, false)) {
            $0.total = 250
            $0.loading = false
            $0.showLoading = false
        }
        XCTAssertEqual(store.state.currentPage, 0)
    }

    @MainActor
    func testLoadFallsBackWhenCurrentPageNoLongerExists() async throws {
        try await configureVerifiedClient()
        stubSearchExpectingStart("200", recordsFiltered: 150)
        stubSearchExpectingStart("100", recordsFiltered: 150)

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 250
        initialState.currentPage = 2

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)
        store.exhaustivity = .off

        await store.send(.load(true))
        // The shrunken total leaves page 2 out of range, so the reducer retries the last page.
        await store.receive(.populateArchives([], 150, false)) {
            $0.currentPage = 1
        }
        await store.receive(.load(false))
        await store.receive(.populateArchives([], 150, false))
        XCTAssertEqual(store.state.currentPage, 1)
    }

    @MainActor
    func testDeletingLastPageReloadsPreviousPage() async throws {
        try await configureVerifiedClient()
        stubSearchExpectingStart("0", recordsFiltered: 100)

        var initialState = makePaginatedState()
        initialState.serverPageSize = 100
        initialState.total = 101
        initialState.currentPage = 1
        initialState.archives = expectedGridStates(in: &initialState, count: 1)
        initialState.archivesToDisplay = initialState.archives

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }
        store.timeout = .seconds(5)
        store.exhaustivity = .off

        await store.send(.deleteSuccess(["archive-0"])) {
            $0.total = 100
            $0.currentPage = 0
        }
        await store.receive(.load(false))
        // Only start=0 is stubbed, so the response proves the reducer reloaded the valid page.
        await store.receive(.populateArchives([], 100, false))

        XCTAssertEqual(store.state.currentPage, 0)
        XCTAssertEqual(store.state.total, 100)
    }

    @MainActor
    func testPagerHiddenUntilThereIsMoreThanOnePage() {
        var state = makePaginatedState()
        state.serverPageSize = 100

        state.total = 80
        XCTAssertEqual(state.pageCount, 1)
        XCTAssertFalse(state.showsPager)

        state.total = 180
        XCTAssertEqual(state.pageCount, 2)
        XCTAssertTrue(state.showsPager)
    }

    @MainActor
    func testReadFilterEmptyStateRequiresLoadedReadArchives() {
        var state = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .library
        )
        state.$hideRead = Shared(value: true)
        let archive = ArchiveItem(
            id: "read-archive",
            name: "Read Archive",
            extension: "zip",
            tags: "",
            isNew: false,
            progress: 10,
            pagecount: 10,
            dateAdded: nil
        )
        state.archives = [GridFeature.State(archive: Shared(value: archive))]

        XCTAssertTrue(state.showsReadFilterEmptyState)

        state.loading = true
        XCTAssertFalse(state.showsReadFilterEmptyState)

        state.loading = false
        state.archives = []
        XCTAssertFalse(state.showsReadFilterEmptyState)
    }

    @MainActor
    func testGridLoadUsesArchiveThumbnailEndpointForNormalArchive() async throws {
        try await configureVerifiedClient()

        let archiveId = "0123456789012345678901234567890123456789"
        let expectedThumbnail = Data([0xFF, 0xD8, 0xFF, 0xDB])
        stubArchiveThumbnail(id: archiveId, data: expectedThumbnail)

        let database = try makeInMemoryDatabase()
        let store = makeGridTestStore(
            archive: makeArchive(id: archiveId, fileExtension: "zip"),
            database: database
        )

        await store.send(.load(false))
        await store.receive(.increaseNonce) {
            $0.nonce = 1
        }

        let savedThumbnail = try database.readArchiveThumbnail(archiveId)
        XCTAssertEqual(savedThumbnail?.thumbnail, expectedThumbnail)
    }

    @MainActor
    func testGridLoadUsesTankoubonThumbnailEndpointForTankArchive() async throws {
        try await configureVerifiedClient()

        let tankId = "TANK_1783084742"
        let expectedThumbnail = Data([0x89, 0x50, 0x4E, 0x47])
        stubTankoubonThumbnail(id: tankId, data: expectedThumbnail)

        let database = try makeInMemoryDatabase()
        let store = makeGridTestStore(
            archive: makeArchive(id: tankId, fileExtension: ".tank"),
            database: database
        )

        await store.send(.load(false))
        await store.receive(.increaseNonce) {
            $0.nonce = 1
        }

        let savedThumbnail = try database.readArchiveThumbnail(tankId)
        XCTAssertEqual(savedThumbnail?.thumbnail, expectedThumbnail)
    }

}

private func configureVerifiedClient() async throws {
    let url = "https://localhost"
    let apiKey = "apiKey"
    UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
    UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)

    stub(condition: isHost("localhost")
            && isPath("/api/info")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "archives_per_page": 100,
              "debug_mode": false,
              "has_password": true,
              "motd": "",
              "name": "LANraragi",
              "nofun_mode": false,
              "server_tracks_progress": true,
              "version": "0.9.30",
              "version_name": "Dodgy Docker"
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }

    _ = try await LANraragiService.shared.verifyClient(url: url, apiKey: apiKey)
}

/// Stubs `/api/search` only for the given `start` offset, so a mismatched offset simply
/// fails to match and surfaces as a missing `populateArchives`.
private func stubSearchExpectingStart(_ start: String, recordsFiltered: Int) {
    stub(condition: isHost("localhost")
            && isPath("/api/search")
            && isMethodGET()
            && containsQueryParams(["start": start])) { _ in
        HTTPStubsResponse(
            data: Data("""
            {"data":[],"recordsFiltered":\(recordsFiltered),"recordsTotal":\(recordsFiltered)}
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubFailedSearchExpectingStart(_ start: String) {
    stub(condition: isHost("localhost")
            && isPath("/api/search")
            && isMethodGET()
            && containsQueryParams(["start": start])) { _ in
        HTTPStubsResponse(
            data: Data(),
            statusCode: 500,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubArchiveThumbnail(id: String, data: Data) {    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(id)/thumbnail")
            && containsQueryParams(["no_fallback": "true", "page": "0"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(data: data, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
    }
}

private func stubTankoubonThumbnail(id: String, data: Data) {
    stub(condition: isHost("localhost")
            && isPath("/api/tankoubons/\(id)/thumbnail")
            && containsQueryParams(["no_fallback": "true"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(data: data, statusCode: 200, headers: ["Content-Type": "image/png"])
    }
}

@MainActor
private func makeGridTestStore(
    archive: ArchiveItem,
    database: AppDatabase
) -> TestStoreOf<GridFeature> {
    TestStore(initialState: GridFeature.State(archive: Shared(value: archive))) {
        GridFeature()
    } withDependencies: {
        $0.appDatabase = database
    }
}

@MainActor
private func makePaginatedState() -> ArchiveListFeature.State {
    let state = ArchiveListFeature.State(
        filter: SearchFilter(category: nil, filter: nil),
        loadOnAppear: false,
        currentTab: .library
    )
    state.$paginateArchiveList = Shared(value: true)
    state.$searchSort = Shared(value: SearchSort.dateAdded.rawValue)
    state.$searchSortOrder = Shared(value: SearchSortOrder.desc.rawValue)
    state.$hideRead = Shared(value: false)
    return state
}

private func makeArchives(count: Int) -> [ArchiveItem] {
    (0..<count).map { index in
        ArchiveItem(
            id: "archive-\(index)",
            name: "Archive \(index)",
            extension: "zip",
            tags: "",
            isNew: false,
            progress: 0,
            pagecount: 10,
            dateAdded: nil
        )
    }
}

/// Rebuilds the grid states the reducer derives from the shared archive store, so tests
/// assert against the same `Shared` references rather than detached copies.
@MainActor
private func expectedGridStates(
    in state: inout ArchiveListFeature.State,
    count: Int
) -> IdentifiedArrayOf<GridFeature.State> {
    let items = makeArchives(count: count)
    items.forEach { item in
        state.$archiveItems.withLock { _ = $0.updateOrAppend(item) }
    }
    return IdentifiedArray(
        uniqueElements: items.compactMap { item in
            Shared(state.$archiveItems[id: item.id]).map { GridFeature.State(archive: $0) }
        }
    )
}

private func makeArchive(id: String, fileExtension: String) -> ArchiveItem {    ArchiveItem(
        id: id,
        name: "Archive",
        extension: fileExtension,
        tags: "",
        isNew: false,
        progress: 0,
        pagecount: 10,
        dateAdded: nil
    )
}

private func makeInMemoryDatabase() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue())
}
