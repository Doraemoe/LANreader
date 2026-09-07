import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class ArchiveListBatchTests: XCTestCase {
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
        await store.send(.deleteButtonTapped)
        await store.send(.alert(.presented(.confirmDelete)))
        await store.receive(.deleteSuccess(["archive-0"]))
        await store.receive(.load(false))
        XCTAssertEqual(store.state.selected, ["archive-1"])
        await store.receive(\.populateArchives)
        await store.finish()
        XCTAssertEqual(store.state.selected, ["archive-1"])
        XCTAssertEqual(store.state.selectMode, .active)
    }

    @MainActor
    func testDoneCannotExitDuringDestructiveBatch() async {
        var state = makePaginatedArchiveListState()
        state.selectMode = .active
        state.loading = true
        state.isDeleting = true
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        await store.send(.toggleSelectionMode)
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
        state.selected = state.cachingArchiveIds
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
