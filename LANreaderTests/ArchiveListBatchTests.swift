import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class ArchiveListBatchTests: XCTestCase {
    @MainActor
    func testCreateTankoubonRejectsSelectedTankoubon() async {
        var state = makePaginatedArchiveListState()
        state.selected = ["archive-0", "TANK_123"]
        let store = TestStore(initialState: state) { ArchiveListFeature() }

        await store.send(.createTankoubon("New Tank")) {
            $0.errorMessage = String(localized: "archive.selected.tankoubon.nested.error")
        }

        XCTAssertEqual(store.state.selected, ["archive-0", "TANK_123"])
        XCTAssertFalse(store.state.loading)
    }

    @MainActor
    func testBatchDownloadExtractsOnlySelectedUncachedArchives() async throws {
        try await configureArchiveListTestClient()
        for id in ["archive-0", "archive-2"] {
            try stubArchiveListExtraction(id: id, pages: ["./api/archives/\(id)/page?path=001.jpg"])
        }
        stubUnexpectedBatchExtraction()
        let database = try makeArchiveListTestDatabase()
        var state = makePaginatedArchiveListState()
        state.archives = expectedArchiveListGridStates(in: &state, count: 3)
        state.archivesToDisplay = state.archives
        state.selectMode = .active
        state.selected = ["archive-0", "archive-2"]
        let store = TestStore(initialState: state) { ArchiveListFeature() } withDependencies: {
            $0.appDatabase = database
        }
        store.exhaustivity = .off
        await store.send(.cacheSelected)
        await store.receive(\.cacheArchiveFinished)
        await store.receive(\.cacheArchiveFinished)
        await store.finish()
        XCTAssertEqual(Set(try database.readAllCached().map(\.id)), ["archive-0", "archive-2"])
        XCTAssertEqual(store.state.selectMode, .active)
        XCTAssertEqual(store.state.successMessage, String(localized: "archive.cache.added"))
    }

    @MainActor
    func testDoneCanExitSelectionWhileLoading() async {
        var state = makePaginatedArchiveListState()
        state.selectMode = .active
        state.selected = ["archive-0"]
        state.loading = true
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        await store.send(.toggleSelectionMode) {
            $0.selectMode = .inactive
            $0.selected = []
        }
    }

    @MainActor
    func testPartialBatchDeletionPreservesFailedSelectionAfterPageReload() async throws {
        try await configureArchiveListTestClient()
        stubArchiveListBatchDelete(path: "/api/archives/archive-0", success: 1)
        stubArchiveListBatchDelete(path: "/api/archives/archive-1", success: 0)
        stubRemainingBatchArchive()
        var state = makePaginatedArchiveListState()
        state.archives = expectedArchiveListGridStates(in: &state, count: 2)
        state.archivesToDisplay = state.archives
        state.total = 2
        state.serverPageSize = 2
        state.selectMode = .active
        state.selected = ["archive-0", "archive-1"]
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        store.exhaustivity = .off
        await store.send(.confirmDelete)
        await store.receive(.deleteFinished(["archive-0"], true))
        await store.receive(.load(false))
        XCTAssertEqual(store.state.selected, ["archive-1"])
        await store.receive(\.populateArchives)
        await store.finish()
        XCTAssertEqual(store.state.selected, ["archive-1"])
        XCTAssertEqual(store.state.selectMode, .active)
    }

    @MainActor
    func testDoneCannotExitDuringBatchAction() async {
        var state = makePaginatedArchiveListState()
        state.selectMode = .active
        state.loading = true
        state.batchActionInProgress = true
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        await store.send(.toggleSelectionMode)
    }

    @MainActor
    func testBatchActionsCannotStartWhileSelectedArchiveIsCaching() async {
        var state = makePaginatedArchiveListState()
        state.selectMode = .active
        state.selected = ["archive-0"]
        state.cachingArchiveIds = ["archive-0"]
        let store = TestStore(initialState: state) { ArchiveListFeature() }

        XCTAssertFalse(store.state.canStartBatchAction)
        await store.send(.confirmDelete)
    }

    @MainActor
    func testBatchAddToCategoryAcceptsExistingMembershipAndKeepsFailuresSelected() async throws {
        try await configureArchiveListTestClient()
        stubCategoryAdd(categoryId: "category", archiveId: "archive-0", success: 1)
        stubCategoryAdd(categoryId: "category", archiveId: "archive-1", success: 1)
        stubCategoryAdd(categoryId: "category", archiveId: "archive-2", success: 0)
        var state = makePaginatedArchiveListState()
        state.selectMode = .active
        state.selected = ["archive-0", "archive-1", "archive-2"]
        state.$categoryItems.withLock {
            $0 = [CategoryItem(
                id: "category", name: "Category", archives: ["archive-0"], search: "", pinned: "0"
            )]
        }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { ArchiveListFeature() }

        await store.send(.addArchivesToCategory("category")) {
            $0.loading = true
            $0.batchActionInProgress = true
        }
        await store.receive(.addArchivesToCategoryFinished("category", ["archive-0", "archive-1"], true)) {
            $0.$categoryItems.withLock { $0[id: "category"]?.archives.append("archive-1") }
            $0.selected = ["archive-2"]
            $0.loading = false
            $0.batchActionInProgress = false
            $0.errorMessage = String(localized: "archive.selected.category.add.error")
        }
        await store.finish()
        XCTAssertEqual(store.state.categoryItems[id: "category"]?.archives, ["archive-0", "archive-1"])
        XCTAssertEqual(store.state.selected, ["archive-2"])
        XCTAssertEqual(store.state.errorMessage, String(localized: "archive.selected.category.add.error"))
        XCTAssertFalse(store.state.loading)
        XCTAssertFalse(store.state.batchActionInProgress)
    }

    @MainActor
    func testBatchRemoveFromStaticCategoryKeepsFailuresSelected() async throws {
        try await configureArchiveListTestClient()
        stubCategoryRemove(categoryId: "category", archiveId: "archive-0", success: 1)
        stubCategoryRemove(categoryId: "category", archiveId: "archive-1", success: 0)
        var state = ArchiveListFeature.State(
            filter: SearchFilter(category: "category", filter: nil),
            loadOnAppear: false,
            currentTab: .category
        )
        state.$paginateArchiveList.withLock { $0 = false }
        state.selectMode = .active
        state.selected = ["archive-0", "archive-1"]
        state.archives = expectedArchiveListGridStates(in: &state, count: 3)
        state.archivesToDisplay = state.archives
        state.$categoryItems.withLock {
            $0 = [CategoryItem(
                id: "category", name: "Category",
                archives: ["archive-0", "archive-1", "archive-2"], search: "", pinned: "0"
            )]
        }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        store.timeout = .seconds(5)

        await store.send(.confirmRemoveFromCategory) {
            $0.loading = true
            $0.batchActionInProgress = true
        }
        await store.receive(.removeFromCategoryFinished("category", ["archive-0"], true)) {
            $0.$categoryItems.withLock { $0[id: "category"]?.archives.removeAll { $0 == "archive-0" } }
            $0.selected = ["archive-1"]
            $0.archives.remove(id: "archive-0")
            $0.archivesToDisplay.remove(id: "archive-0")
            $0.loading = false
            $0.batchActionInProgress = false
            $0.errorMessage = String(localized: "archive.selected.category.remove.error")
        }
        await store.finish()
        XCTAssertEqual(store.state.categoryItems[id: "category"]?.archives, ["archive-1", "archive-2"])
        XCTAssertNotNil(store.state.archives[id: "archive-2"])
    }

    @MainActor
    func testDeletingTankoubonReloadsMembersAndKeepsFailedSelection() async throws {
        try await configureArchiveListTestClient()
        stubArchiveListBatchDelete(path: "/api/tankoubons/TANK_1", success: 1)
        stubArchiveListBatchDelete(path: "/api/archives/archive-failed", success: 0)
        stubTankoubonDeletionReload()
        var state = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil), loadOnAppear: false, currentTab: .library
        )
        state.$paginateArchiveList.withLock { $0 = false }
        state.$lastTagRefresh.withLock { $0 = Date().timeIntervalSince1970 }
        state.selectMode = .active
        state.selected = ["TANK_1", "archive-failed"]
        state.archives = IdentifiedArray(uniqueElements: ["TANK_1", "archive-failed"].map {
            GridFeature.State(archive: Shared(value: ArchiveItem(
                id: $0, name: $0, extension: "zip", tags: "", isNew: false,
                progress: 0, pagecount: 10, dateAdded: nil
            )))
        })
        state.archivesToDisplay = state.archives
        state.total = 2
        state.$categoryItems.withLock {
            $0 = [CategoryItem(
                id: "category", name: "Category", archives: ["TANK_1", "archive-failed"],
                search: "", pinned: "0"
            )]
        }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        store.exhaustivity = .off

        await store.send(.confirmDelete)
        await store.receive(\.deleteFinished)
        await store.receive(\.populateArchives)
        await store.finish()

        XCTAssertNil(store.state.archives[id: "TANK_1"])
        XCTAssertNotNil(store.state.archives[id: "archive-member"])
        XCTAssertEqual(store.state.selected, ["archive-failed"])
        XCTAssertEqual(store.state.categoryItems[id: "category"]?.archives, ["archive-failed"])
        XCTAssertFalse(store.state.preserveSelectionOnNextPopulate)
    }

    @MainActor
    func testChangingFilterClearsSelection() async {
        var state = makePaginatedArchiveListState()
        state.selected = ["archive-0"]
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        let filter = SearchFilter(category: nil, filter: "new query")
        await store.send(.setFilter(filter)) {
            $0.filter = filter
            $0.selected = []
        }
    }

    @MainActor
    func testBatchDownloadReportsFailuresOnceAndKeepsFailedSelection() async {
        var state = makePaginatedArchiveListState()
        state.archives = expectedArchiveListGridStates(in: &state, count: 3)
        state.archivesToDisplay = state.archives
        state.selectMode = .active
        state.cachingArchiveIds = ["archive-0", "archive-1", "archive-2"]
        state.batchCachingArchiveIds = state.cachingArchiveIds
        state.selected = .init(state.cachingArchiveIds)
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        for id in ["archive-0", "archive-1"] {
            await store.send(.cacheArchiveFailed(id, "Failed")) {
                $0.cachingArchiveIds.remove(id)
                $0.batchCachingArchiveIds.remove(id)
                $0.batchCacheErrors = ["Failed"]
            }
            XCTAssertTrue(store.state.errorMessage.isEmpty)
        }
        await store.send(.cacheArchiveFinished("archive-2")) {
            $0.cachingArchiveIds = []
            $0.batchCachingArchiveIds = []
            $0.batchCacheErrors = []
            $0.errorMessage = "Failed"
            $0.selected.remove("archive-2")
        }
        XCTAssertTrue(store.state.successMessage.isEmpty)
    }
    override func tearDownWithError() throws {
        UserDefaults.resetStandardUserDefaults()
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    func testBatchDownloadReportsSuccessOnlyAfterLastArchive() async {
        var state = makePaginatedArchiveListState()
        state.cachingArchiveIds = ["a", "b"]
        state.batchCachingArchiveIds = state.cachingArchiveIds
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        await store.send(.cacheArchiveFinished("a")) {
            $0.cachingArchiveIds = ["b"]
            $0.batchCachingArchiveIds = ["b"]
            $0.batchCacheHadSuccess = true
        }
        XCTAssertTrue(store.state.successMessage.isEmpty)
        await store.send(.cacheArchiveFinished("b")) {
            $0.cachingArchiveIds = []
            $0.batchCachingArchiveIds = []
            $0.batchCacheHadSuccess = false
            $0.successMessage = String(localized: "archive.cache.added")
        }
    }
}

private func stubUnexpectedBatchExtraction() {
    stub(condition: isPath("/api/archives/archive-1/extract")) { _ in
        XCTFail("Unselected archive must not be extracted")
        return HTTPStubsResponse(data: Data(), statusCode: 500, headers: nil)
    }
}

private func stubRemainingBatchArchive() {
    stub(condition: isPath("/api/search") && isMethodGET() && containsQueryParams(["start": "0"])) { _ in
        HTTPStubsResponse(data: Data("""
        {"data":[{"arcid":"archive-1","extension":"zip","isnew":"false","tags":"",
        "title":"Archive 1","pagecount":10,"progress":0}],"recordsFiltered":1,"recordsTotal":1}
        """.utf8), statusCode: 200, headers: ["Content-Type": "application/json"])
    }
}

private func stubTankoubonDeletionReload() {
    stub(condition: isHost("localhost") && isPath("/api/search") && isMethodGET()
            && containsQueryParams(["start": "0"])) { _ in
        HTTPStubsResponse(data: Data("""
        {"data":[
          {"arcid":"archive-member","extension":"zip","isnew":"false","tags":"",
           "title":"Member","pagecount":10,"progress":0},
          {"arcid":"archive-failed","extension":"zip","isnew":"false","tags":"",
           "title":"Failed","pagecount":10,"progress":0}
        ],"recordsFiltered":2,"recordsTotal":2}
        """.utf8), statusCode: 200, headers: ["Content-Type": "application/json"])
    }
}

private func stubCategoryAdd(categoryId: String, archiveId: String, success: Int) {
    stub(condition: isHost("localhost")
            && isPath("/api/categories/\(categoryId)/\(archiveId)")
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(
            data: Data("{\"success\":\(success)}".utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubCategoryRemove(categoryId: String, archiveId: String, success: Int) {
    stub(condition: isHost("localhost")
            && isPath("/api/categories/\(categoryId)/\(archiveId)")
            && isMethodDELETE()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { request in
        XCTAssertNil(request.url?.query)
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        return HTTPStubsResponse(
            data: Data("{\"success\":\(success)}".utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}
