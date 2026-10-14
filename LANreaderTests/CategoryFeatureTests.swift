import XCTest
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
import os
@testable import LANreader

final class CategoryFeatureTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("https://localhost", forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set("apiKey", forKey: SettingsKey.lanraragiApiKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
    }

    @MainActor
    func testFailedInitialLoadDismissesOverlayAndAllowsRefresh() async throws {
        let offline = OSAllocatedUnfairLock(initialState: true)
        stub(condition: isHost("localhost") && isPath("/api/categories")) { @Sendable request in
            XCTAssertEqual(request.httpMethod, "GET")
            if offline.withLock({ $0 }) {
                return HTTPStubsResponse(error: URLError(.notConnectedToInternet))
            }
            return HTTPStubsResponse(jsonObject: [[
                "id": "SET_recovered", "name": "Recovered", "archives": [], "search": "", "pinned": "0"
            ]], statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        let state = CategoryFeature.State()
        state.$categoryItems.withLock { $0 = [] }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { CategoryFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }
        store.exhaustivity = .off
        await store.send(.loadCategory(true)) {
            $0.showLoading = true
        }
        await store.receive(\.setErrorMessage)
        XCTAssertFalse(store.state.showLoading)
        XCTAssertFalse(store.state.errorMessage.isEmpty)
        XCTAssertTrue(store.state.categoryItems.isEmpty)
        await store.send(.setErrorMessage("")) {
            $0.errorMessage = ""
        }
        offline.withLock { $0 = false }
        await store.send(.loadCategory(false))
        await store.receive(\.populateCategory)
        await store.finish()
        XCTAssertEqual(store.state.categoryItems.map(\.id), ["SET_recovered"])
        XCTAssertFalse(store.state.showLoading)
    }

    @MainActor
    func testCategoryScreenPreservesServerOrderWithinPinnedGroups() async {
        let expected = stubCategoryOrder()
        let state = CategoryFeature.State()
        state.$categoryItems.withLock { $0 = [] }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { CategoryFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }

        await store.send(.loadCategory(true)) {
            $0.showLoading = true
        }
        await store.receive(\.populateCategory) {
            $0.$categoryItems.withLock { $0 = IdentifiedArray(uniqueElements: expected) }
            $0.showLoading = false
        }
        await store.finish()
    }

    @MainActor
    func testArchiveSelectionPreservesServerOrderWithinPinnedGroups() async {
        let expected = stubCategoryOrder()
        let state = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil), loadOnAppear: false, currentTab: .library
        )
        state.$categoryItems.withLock { $0 = [] }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { ArchiveListFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }

        await store.send(.loadCategory)
        await store.receive(\.populateCategory) {
            $0.$categoryItems.withLock { $0 = IdentifiedArray(uniqueElements: expected) }
        }
        await store.finish()
    }

    @MainActor
    func testArchiveDetailsPreservesServerOrderWithinPinnedGroups() async {
        let expected = stubCategoryOrder()
        let archive = ArchiveItem(
            id: "archive", name: "Archive", extension: "zip", tags: "",
            isNew: false, progress: 0, pagecount: 1, dateAdded: nil
        )
        let state = ArchiveDetailsFeature.State(archive: Shared(value: archive))
        state.$categoryItems.withLock { $0 = [] }
        defer { state.$categoryItems.withLock { $0 = [] } }
        let store = TestStore(initialState: state) { ArchiveDetailsFeature() } withDependencies: {
            $0.lanraragiService = LANraragiService(backgroundSessionConfiguration: .ephemeral)
        }

        await store.send(.loadCategory)
        await store.receive(\.populateCategory) {
            $0.$categoryItems.withLock { $0 = IdentifiedArray(uniqueElements: expected) }
        }
        await store.finish()
    }

    @MainActor
    func testClearingErrorMessagePreservesActiveLoad() async {
        var state = CategoryFeature.State()
        state.showLoading = true
        state.errorMessage = "Previous request failed"
        let store = TestStore(initialState: state) { CategoryFeature() }
        await store.send(.setErrorMessage("")) {
            $0.errorMessage = ""
        }
    }
}

private func stubCategoryOrder() -> [CategoryItem] {
    let items = [("SET_C", "C", "0"), ("SET_Z", "Z", "1"), ("SET_A", "A", "0"),
                 ("SET_Y", "Y", "1"), ("SET_B", "B", "0")].map {
        CategoryItem(id: $0.0, name: $0.1, archives: [], search: "", pinned: $0.2)
    }
    stub(condition: isHost("localhost") && isPath("/api/categories")) { @Sendable request in
        XCTAssertEqual(request.httpMethod, "GET")
        return HTTPStubsResponse(
            jsonObject: items.map { ["id": $0.id, "name": $0.name, "pinned": $0.pinned] },
            statusCode: 200, headers: ["Content-Type": "application/json"]
        )
    }
    return [items[1], items[3], items[0], items[2], items[4]]
}
