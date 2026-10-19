import XCTest
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

final class ArchiveListHideReadTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
        super.tearDown()
    }

    @MainActor
    func testReadFilterEmptyStateWaitsForRemainingPagesInScrollMode() {
        var state = makePaginatedArchiveListState()
        state.$paginateArchiveList = Shared(value: false)
        state.$hideRead = Shared(value: true)
        state.archives = [GridFeature.State(archive: Shared(value: makeSearchArchive(id: "read", read: true)))]
        state.total = 5
        XCTAssertFalse(state.showsReadFilterEmptyState)

        state.$paginateArchiveList = Shared(value: true)
        XCTAssertTrue(state.showsReadFilterEmptyState)
    }

    @MainActor
    func testHideReadKeepsLoadingPastFullyReadPages() async throws {
        try await configureArchiveListTestClient()
        stubSearchPage(start: "0", archives: [("read-0", true), ("read-1", true)], total: 5)
        stubSearchPage(start: "2", archives: [("read-2", true), ("read-3", true)], total: 5)
        stubSearchPage(start: "4", archives: [("unread-4", false)], total: 5)
        let store = TestStore(initialState: makeHideReadScrollState()) { ArchiveListFeature() }
        store.timeout = .seconds(5)
        store.exhaustivity = .off

        await store.send(.load)
        await store.receive(\.populateArchives)
        await store.receive(\.appendArchives)
        await store.receive(\.populateArchives)
        await store.receive(\.appendArchives)
        await store.receive(\.populateArchives)
        await store.finish()

        XCTAssertEqual(store.state.archives.count, 5)
        XCTAssertEqual(store.state.archivesToDisplay.ids.elements, ["unread-4"])
        XCTAssertFalse(store.state.showsReadFilterEmptyState)
    }

    @MainActor
    func testHideReadStopsAtTheEndWhenEveryArchiveIsRead() async throws {
        try await configureArchiveListTestClient()
        stubSearchPage(start: "0", archives: [("read-0", true), ("read-1", true)], total: 4)
        stubSearchPage(start: "2", archives: [("read-2", true), ("read-3", true)], total: 4)
        let store = TestStore(initialState: makeHideReadScrollState()) { ArchiveListFeature() }
        store.timeout = .seconds(5)
        store.exhaustivity = .off

        await store.send(.load)
        await store.receive(\.populateArchives)
        await store.receive(\.appendArchives)
        await store.receive(\.populateArchives)
        await store.finish()

        XCTAssertEqual(store.state.archives.count, 4)
        XCTAssertTrue(store.state.archivesToDisplay.isEmpty)
        XCTAssertTrue(store.state.showsReadFilterEmptyState)
    }

    @MainActor
    func testTurningOnHideReadLoadsNextPageWhenArchivesAreHidden() async throws {
        try await configureArchiveListTestClient()
        stubSearchPage(start: "2", archives: [("unread-2", false), ("unread-3", false)], total: 4)
        var state = makeHideReadScrollState()
        state.$hideRead = Shared(value: false)
        state.archives = IdentifiedArray(uniqueElements: [
            GridFeature.State(archive: Shared(value: makeSearchArchive(id: "read-0", read: true))),
            GridFeature.State(archive: Shared(value: makeSearchArchive(id: "unread-1", read: false)))
        ])
        state.archivesToDisplay = state.archives
        state.total = 4
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        store.timeout = .seconds(5)
        store.exhaustivity = .off

        await store.send(.toggleHideRead)
        await store.receive(.appendArchives("2"))
        await store.receive(\.populateArchives)
        await store.finish()

        XCTAssertEqual(store.state.archivesToDisplay.ids.elements, ["unread-1", "unread-2", "unread-3"])
    }
}

@MainActor
private func makeHideReadScrollState() -> ArchiveListFeature.State {
    let state = makePaginatedArchiveListState()
    state.$paginateArchiveList = Shared(value: false)
    state.$hideRead = Shared(value: true)
    return state
}

private func makeSearchArchive(id: String, read: Bool) -> ArchiveItem {
    ArchiveItem(
        id: id, name: id, extension: "zip", tags: "",
        isNew: false, progress: read ? 10 : 0, pagecount: 10, dateAdded: nil
    )
}

private func stubSearchPage(start: String, archives: [(id: String, read: Bool)], total: Int) {
    let data = archives.map { archive in
        [
            "arcid": archive.id, "extension": "zip", "isnew": "false", "tags": "",
            "title": archive.id, "pagecount": 10, "progress": archive.read ? 10 : 0
        ] as [String: Any]
    }
    stub(condition: isHost("localhost")
            && isPath("/api/search")
            && isMethodGET()
            && containsQueryParams(["start": start])) { _ in
        HTTPStubsResponse(
            jsonObject: ["data": data, "recordsFiltered": total, "recordsTotal": total],
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}
