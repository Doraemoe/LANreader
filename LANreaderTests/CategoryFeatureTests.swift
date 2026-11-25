import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
import SwiftUI
import UIKit
import os
@testable import LANreader

final class CategoryFeatureTests: LANreaderTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.set("https://localhost", forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set("apiKey", forKey: SettingsKey.lanraragiApiKey)
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

final class CategoryTabNavigationTests: LANreaderTestCase {
    @MainActor
    func testCategoryNavigationFlowPushesGridReaderDetailsTagSearchAndPopsOnDelete() async throws {
        let category = makeCategoryTestItem(id: "SET_1", name: "Favorites")
        let archive = makeCategoryTestArchive(id: "catArc1", name: "First", tags: "artist:e auo")
        let store = try makeCategoryTabTestStore()
        defer { clearSharedArchiveItems() }

        await store.send(.categoryTapped(category))
        let categoryID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .categoryArchives(categoryState) = store.state.path[id: categoryID] else {
            return XCTFail("Expected pushed category archive list state")
        }
        XCTAssertEqual(categoryState.id, "SET_1")
        XCTAssertEqual(categoryState.name, "Favorites")
        XCTAssertEqual(categoryState.archiveList.filter, SearchFilter(category: "SET_1", filter: nil))
        XCTAssertEqual(categoryState.archiveList.currentTab, .category)

        await store.send(.path(.element(
            id: categoryID,
            action: .categoryArchives(.archiveList(.populateArchives([archive], 1, false)))
        )))
        await store.send(.path(.element(
            id: categoryID,
            action: .categoryArchives(.archiveList(.openReader(archiveId: archive.id, fromStart: true)))
        )))
        let readerID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .reader(readerState) = store.state.path[id: readerID] else {
            return XCTFail("Expected pushed reader state")
        }
        XCTAssertEqual(readerState.currentArchiveId, archive.id)
        XCTAssertTrue(readerState.fromStart)
        XCTAssertEqual(readerState.allArchives.ids, [archive.id])

        await store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
        let detailsID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .details(detailsState) = store.state.path[id: detailsID] else {
            return XCTFail("Expected pushed details state")
        }
        XCTAssertEqual(detailsState.archive.id, archive.id)
        XCTAssertEqual(detailsState.title, "First")

        await store.send(.path(.element(id: detailsID, action: .details(.tagTapped(" artist:e auo ")))))
        let tagSearchID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .search(tagSearchState) = store.state.path[id: tagSearchID] else {
            return XCTFail("Expected pushed tag search state")
        }
        XCTAssertEqual(tagSearchState.keyword, "artist:e auo")

        await store.send(.path(.popFrom(id: tagSearchID)))
        XCTAssertEqual(Array(store.state.path.ids), [categoryID, readerID, detailsID])

        await store.send(.path(.element(id: detailsID, action: .details(.deleteSuccess))))
        XCTAssertEqual(Array(store.state.path.ids), [categoryID])
    }

    @MainActor
    func testCategoryNestedDeletePopsOnlyInnerReaderAndDetails() async throws {
        let category = makeCategoryTestItem(id: "SET_1", name: "Favorites")
        let firstArchive = makeCategoryTestArchive(id: "catArc1", name: "First", tags: "artist:e auo")
        let secondArchive = makeCategoryTestArchive(id: "catArc2", name: "Second", tags: "artist:e auo")
        let store = try makeCategoryTabTestStore()
        defer { clearSharedArchiveItems() }

        await store.send(.categoryTapped(category))
        let categoryID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(
            id: categoryID,
            action: .categoryArchives(.archiveList(.populateArchives([firstArchive], 1, false)))
        )))
        await store.send(.path(.element(
            id: categoryID,
            action: .categoryArchives(.archiveList(.openReader(archiveId: firstArchive.id, fromStart: false)))
        )))
        let readerID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
        let detailsID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: detailsID, action: .details(.tagTapped("artist:e auo")))))
        let tagSearchID = try XCTUnwrap(store.state.path.ids.last)

        await store.send(.path(.element(
            id: tagSearchID,
            action: .search(.archiveList(.populateArchives([secondArchive], 1, false)))
        )))
        await store.send(.path(.element(
            id: tagSearchID,
            action: .search(.archiveList(.openReader(archiveId: secondArchive.id, fromStart: false)))
        )))
        let nestedReaderID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: nestedReaderID, action: .reader(.openDetailsTapped))))
        let nestedDetailsID = try XCTUnwrap(store.state.path.ids.last)

        await store.send(.path(.element(id: nestedDetailsID, action: .details(.deleteSuccess))))
        XCTAssertEqual(Array(store.state.path.ids), [categoryID, readerID, detailsID, tagSearchID])
    }

    @MainActor
    func testCategoryNavigationControllerPushesAndPopsWithStore() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let category = makeCategoryTestItem(id: "SET_1", name: "Favorites")
        let archive = makeCategoryTestArchive(id: "catArc1", name: "First", tags: "artist:e auo")
        let initialState = CategoryFeature.State()
        initialState.$categoryItems.withLock { $0 = [category] }
        defer {
            initialState.$categoryItems.withLock { $0 = [] }
            clearSharedArchiveItems()
        }

        try await withDependencies {
            $0.appDatabase = database
        } operation: {
            let store = Store(initialState: initialState) { CategoryFeature() }
            let nav = makeCategoryNavigationController(store: store)
            nav.loadViewIfNeeded()
            nav.topViewController?.loadViewIfNeeded()
            XCTAssertEqual(nav.viewControllers.count, 1)
            XCTAssertTrue(nav.topViewController is UICategoryListViewController)

            sendWithoutAnimation(store, .categoryTapped(category))
            await waitUntil { nav.viewControllers.count == 2 }
            XCTAssertTrue(nav.topViewController is UICategoryArchiveGridController)
            nav.topViewController?.loadViewIfNeeded()

            let categoryID = try XCTUnwrap(store.path.ids.last)
            _ = store.send(.path(.element(
                id: categoryID,
                action: .categoryArchives(.archiveList(.populateArchives([archive], 1, false)))
            )))
            sendWithoutAnimation(store, .path(.element(
                id: categoryID,
                action: .categoryArchives(.archiveList(.openReader(archiveId: archive.id, fromStart: false)))
            )))
            await waitUntil { nav.viewControllers.count == 3 }
            XCTAssertTrue(nav.topViewController is UIArchiveReaderController)

            let readerID = try XCTUnwrap(store.path.ids.last)
            sendWithoutAnimation(store, .path(.element(id: readerID, action: .reader(.openDetailsTapped))))
            await waitUntil { nav.viewControllers.count == 4 }
            XCTAssertTrue(nav.topViewController is UIHostingController<ArchiveDetailsV2>)

            let detailsID = try XCTUnwrap(store.path.ids.last)
            sendWithoutAnimation(store, .path(.element(id: detailsID, action: .details(.deleteSuccess))))
            await waitUntil { nav.viewControllers.count == 2 }
            XCTAssertTrue(nav.topViewController is UICategoryArchiveGridController)
            XCTAssertEqual(Array(store.path.ids), [categoryID])
        }
    }
}

@MainActor
private func sendWithoutAnimation(
    _ store: StoreOf<CategoryFeature>,
    _ action: CategoryFeature.Action
) {
    withUITransaction(\.uiKit.disablesAnimations, true) {
        _ = store.send(action)
    }
}

@MainActor
private func makeCategoryTabTestStore() throws -> TestStoreOf<CategoryFeature> {
    let database = try AppDatabase(DatabaseQueue())
    let store = TestStore(initialState: CategoryFeature.State()) {
        CategoryFeature()
    } withDependencies: {
        $0.appDatabase = database
    }
    store.exhaustivity = .off
    return store
}

private func clearSharedArchiveItems() {
    @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
    $archiveItems.withLock { $0 = [] }
}

private func makeCategoryTestItem(id: String, name: String) -> CategoryItem {
    CategoryItem(id: id, name: name, archives: [], search: "", pinned: "0")
}

private func makeCategoryTestArchive(id: String, name: String, tags: String) -> ArchiveItem {
    ArchiveItem(
        id: id,
        name: name,
        extension: "zip",
        tags: tags,
        isNew: false,
        progress: 0,
        pagecount: 10,
        dateAdded: nil
    )
}
