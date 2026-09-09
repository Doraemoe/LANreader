import XCTest
import ComposableArchitecture
import GRDB
import UIKit
@testable import LANreader

final class ArchiveListSelectionTests: XCTestCase {
    @MainActor
    func testCategorySelectionPreservesHiddenTabBar() async throws {
        var list = makeSelectionState(count: 1)
        list.currentTab = .category
        list.filter = SearchFilter(category: "category", filter: nil)
        list.$categoryItems.withLock {
            $0 = [CategoryItem(
                id: "category", name: "Category", archives: ["archive-0"], search: "", pinned: "0"
            )]
        }
        defer { list.$categoryItems.withLock { $0 = [] } }
        let state = CategoryArchiveListFeature.State(id: "category", name: "Category", archiveList: list)
        let store = Store(initialState: state) {
            CategoryArchiveListFeature()
        }
        let controller = UICategoryArchiveGridController(store: store)
        try await checkSharedSelection(
            controller: controller, store: store.scope(\.archiveList, action: \.archiveList), pushed: true
        )
    }

    @MainActor
    func testSearchSelectionRestoresTabBarAndSearchInput() async throws {
        let database = try AppDatabase(DatabaseQueue())
        try await withDependencies {
            $0.appDatabase = database
        } operation: {
            var state = SearchFeature.State()
            state.archiveList = makeSelectionState(count: 1)
            state.archiveList.currentTab = .search
            let store = Store(initialState: state) {
                SearchFeature().dependency(\.appDatabase, database)
            }
            let controller = UISearchViewV2Controller(store: store)
            try await checkSharedSelection(
                controller: controller, store: store.scope(\.archiveList, action: \.archiveList), pushed: false
            )
            let searchBar = try XCTUnwrap(controller.navigationItem.searchController?.searchBar
                ?? controller.view.subviews.compactMap { $0 as? UISearchBar }.first)
            store.send(.archiveList(.toggleSelectionMode))
            await Task.yield()
            XCTAssertFalse(searchBar.isUserInteractionEnabled)
            XCTAssertFalse(searchBar.isFirstResponder)
            store.send(.archiveList(.cacheSelected))
            await Task.yield()
            XCTAssertEqual(store.archiveList.selectMode, .active)
            XCTAssertFalse(searchBar.isUserInteractionEnabled)
            store.send(.archiveList(.toggleSelectionMode))
            await Task.yield()
            XCTAssertTrue(searchBar.isUserInteractionEnabled)
        }
    }

    @MainActor
    func testNewSearchClearsSelection() async {
        var state = SearchFeature.State()
        state.archiveList.selected = ["old-result"]
        let store = TestStore(initialState: state) { SearchFeature() }
        await store.send(.searchSubmit("new query")) {
            $0.archiveList.filter = SearchFilter(category: nil, filter: "new query")
            $0.archiveList.selected = []
        }
    }

    @MainActor
    func testLibraryToolbarUsesPageColorsInLightAndDarkAppearance() async throws {
        var state = LibraryFeature.State()
        state.archiveList = makeSelectionState(count: 1)
        let store = Store(initialState: state) { LibraryFeature() }
        let controller = UILibraryListViewController(store: store, navigationHelper: NavigationHelper())
        let navigation = UINavigationController(rootViewController: controller)
        navigation.loadViewIfNeeded()
        controller.loadViewIfNeeded()
        store.send(.archiveList(.toggleSelectionMode))
        await Task.yield()
        for style in [UIUserInterfaceStyle.light, .dark] {
            controller.overrideUserInterfaceStyle = style
            await Task.yield()
            let expected = UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            let count = try XCTUnwrap(controller.toolbarItems?.first)
            let download = try XCTUnwrap(controller.toolbarItems?[4])
            XCTAssertEqual(count.tintColor, expected)
            XCTAssertEqual(download.tintColor, expected)
        }
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testLibrarySelectionControlsToolbarAndInterceptsReaderNavigation() async throws {
        var libraryState = LibraryFeature.State()
        libraryState.archiveList = makeSelectionState(count: 2)
        libraryState.archiveList.$categoryItems.withLock {
            $0 = [
                CategoryItem(id: "static", name: "Static", archives: [], search: "", pinned: "0"),
                CategoryItem(id: "dynamic", name: "Dynamic", archives: [], search: "tag:test", pinned: "0")
            ]
        }
        defer { libraryState.archiveList.$categoryItems.withLock { $0 = [] } }
        let libraryStore = Store(initialState: libraryState) { LibraryFeature() }
        let store = libraryStore.scope(\.archiveList, action: \.archiveList)
        let parent = UILibraryListViewController(store: libraryStore, navigationHelper: NavigationHelper())
        let navigation = UINavigationController(rootViewController: parent)
        let tabs = UITabBarController()
        tabs.viewControllers = [navigation]
        tabs.loadViewIfNeeded()
        navigation.loadViewIfNeeded()
        parent.loadViewIfNeeded()
        let controller = try XCTUnwrap(parent.children.first as? UIArchiveListViewController)
        await Task.yield()

        XCTAssertNotNil(parent.navigationItem.rightBarButtonItem?.menu)
        XCTAssertEqual(parent.navigationItem.leftBarButtonItems?.count, 1)
        store.send(.toggleSelectionMode)
        await Task.yield()
        XCTAssertEqual(parent.navigationItem.rightBarButtonItem?.title, String(localized: "done"))
        XCTAssertFalse(navigation.isToolbarHidden)
        XCTAssertTrue(parent.navigationItem.leftBarButtonItems?.isEmpty ?? true)
        if #available(iOS 18.0, *) {
            XCTAssertTrue(tabs.isTabBarHidden)
        } else {
            XCTAssertTrue(tabs.tabBar.isHidden)
        }
        XCTAssertEqual(parent.toolbarItems?.last?.isEnabled, false)

        controller.collectionView(controller.collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))
        await Task.yield()
        XCTAssertEqual(store.selected, ["archive-0"])
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertEqual(parent.toolbarItems?.last?.isEnabled, true)
        XCTAssertEqual(parent.toolbarItems?[2].menu?.children.map(\.title), ["Static"])
        XCTAssertEqual(parent.toolbarItems?[2].isEnabled, true)
        let count = try XCTUnwrap(parent.toolbarItems?.first)
        XCTAssertEqual(count.title, String(format: String(localized: "archive.selected"), 1))
        XCTAssertTrue(count.isEnabled)
        XCTAssertNil(count.customView)
        XCTAssertNil(controller.collectionView(
            controller.collectionView, contextMenuConfigurationForItemAt: IndexPath(item: 0, section: 0), point: .zero
        ))

        store.send(.toggleSelectionMode)
        await Task.yield()
        XCTAssertTrue(store.selected.isEmpty)
        XCTAssertTrue(navigation.isToolbarHidden)
        if #available(iOS 18.0, *) {
            XCTAssertFalse(tabs.isTabBarHidden)
        } else {
            XCTAssertFalse(tabs.tabBar.isHidden)
        }
        XCTAssertNotNil(parent.navigationItem.rightBarButtonItem?.menu)
        XCTAssertEqual(parent.navigationItem.leftBarButtonItems?.count, 1)
    }

    @MainActor
    func testBatchDownloadSkipsAlreadyCachedArchivesAndKeepsSelectionMode() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let state = makeSelectionState(count: 3)
        // Existing cache entries exercise the shared duplicate-download guard.
        for id in ["archive-0", "archive-2"] {
            var cache = ArchiveCache(
                id: id, title: id, tags: "", thumbnail: nil,
                cached: true, totalPages: 1, lastUpdate: Date()
            )
            try database.saveCache(&cache)
        }
        let store = TestStore(initialState: state) { ArchiveListFeature() } withDependencies: {
            $0.appDatabase = database
        }
        await store.send(.toggleSelectionMode) { $0.selectMode = .active }
        await store.send(.addSelect("archive-0")) { $0.selected = ["archive-0"] }
        await store.send(.addSelect("archive-2")) { $0.selected = ["archive-0", "archive-2"] }
        await store.send(.cacheSelected) {
            $0.selected = []
        }
        await store.finish()
    }

    @MainActor
    func testSelectionUsesTapOrder() async {
        let store = TestStore(initialState: makeSelectionState(count: 2)) { ArchiveListFeature() }
        await store.send(.toggleSelectionMode) { $0.selectMode = .active }
        await store.send(.addSelect("archive-0")) { $0.selected = ["archive-0"] }
        await store.send(.addSelect("archive-1")) { $0.selected = ["archive-0", "archive-1"] }
        await store.send(.removeSelect("archive-0")) { $0.selected = ["archive-1"] }
        await store.send(.addSelect("archive-0")) { $0.selected = ["archive-1", "archive-0"] }
    }

    @MainActor
    func testCacheSelectionUsesNativeToolbarAndVisibleCount() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = Store(initialState: CacheFeature.State()) { CacheFeature() } withDependencies: {
            $0.appDatabase = database
        }
        let controller = UICacheViewController(store: store, navigationHelper: NavigationHelper())
        let navigation = UINavigationController(rootViewController: controller)
        navigation.loadViewIfNeeded()
        controller.loadViewIfNeeded()
        store.send(.toggleSelectionMode)
        await Task.yield()
        XCTAssertFalse(navigation.isToolbarHidden)
        let count = try XCTUnwrap(controller.toolbarItems?.first)
        XCTAssertEqual(count.title, String(format: String(localized: "archive.selected"), 0))
        XCTAssertTrue(count.isEnabled)
        XCTAssertNil(count.customView)
        XCTAssertEqual(controller.toolbarItems?.last?.accessibilityLabel, String(localized: "archive.cache.remove"))
        XCTAssertEqual(controller.toolbarItems?.last?.isEnabled, false)
        store.send(.toggleSelectionMode)
        await Task.yield()
        XCTAssertTrue(navigation.isToolbarHidden)
    }

}
@MainActor
private func makeSelectionState(count: Int) -> ArchiveListFeature.State {
    var state = ArchiveListFeature.State(
        filter: SearchFilter(category: nil, filter: nil), loadOnAppear: false, currentTab: .library
    )
    let archives = (0..<count).map { index in
        ArchiveItem(
            id: "archive-\(index)", name: "Archive \(index)", extension: "zip",
            tags: "", isNew: false, progress: 0, pagecount: 10, dateAdded: nil
        )
    }
    state.archives = IdentifiedArray(uniqueElements: archives.map {
        GridFeature.State(archive: Shared(value: $0))
    })
    state.archivesToDisplay = state.archives
    return state
}

@MainActor
// swiftlint:disable:next function_body_length
private func checkSharedSelection(
    controller: UIViewController, store: StoreOf<ArchiveListFeature>, pushed: Bool
) async throws {
    let database = try AppDatabase(DatabaseQueue())
    let thumbnailData = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { _ in }
    var thumbnail = ArchiveThumbnail(id: "archive-0", thumbnail: thumbnailData, lastUpdate: Date())
    try database.saveArchiveThumbnail(&thumbnail)
    try await withDependencies {
        $0.appDatabase = database
    } operation: {
        let navigation = UINavigationController()
        navigation.viewControllers = pushed ? [UIViewController(), controller] : [controller]
        let tabs = UITabBarController()
        tabs.viewControllers = [navigation]
        tabs.loadViewIfNeeded()
        navigation.loadViewIfNeeded()
        controller.loadViewIfNeeded()
        let list = try XCTUnwrap(controller.children.compactMap { $0 as? UIArchiveListViewController }.first)
        await Task.yield()
        let menu = controller.navigationItem.rightBarButtonItem?.menu
        XCTAssertEqual(menu?.children.last?.title, String(localized: "select"))
        store.send(.toggleSelectionMode)
        await Task.yield()
        XCTAssertFalse(navigation.isToolbarHidden)
        XCTAssertTrue(controller.navigationItem.hidesBackButton)
        if #available(iOS 18.0, *) { XCTAssertTrue(tabs.isTabBarHidden) }
        if #available(iOS 18.0, *) {
            tabs.setTabBarHidden(false, animated: false)
            list.view.setNeedsLayout()
            list.view.layoutIfNeeded()
            XCTAssertTrue(tabs.isTabBarHidden)
        }
        list.collectionView(list.collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))
        await Task.yield()
        XCTAssertEqual(store.selected, ["archive-0"])
        XCTAssertEqual(controller.toolbarItems?.count, 6)
        XCTAssertEqual(controller.toolbarItems?.last?.accessibilityLabel, String(localized: "archive.delete"))
        XCTAssertEqual(
            controller.toolbarItems?[3].accessibilityLabel,
            String(localized: "archive.selected.tankoubon.create")
        )
        XCTAssertEqual(controller.toolbarItems?[4].accessibilityLabel, String(localized: "archive.cache.add"))
        XCTAssertEqual(controller.toolbarItems?.last?.isEnabled, true)
        if store.currentStaticCategoryId != nil {
            XCTAssertEqual(controller.toolbarItems?[2].accessibilityLabel, String(localized: "remove"))
            XCTAssertNil(controller.toolbarItems?[2].menu)
            XCTAssertEqual(controller.toolbarItems?[2].isEnabled, true)
        } else {
            XCTAssertEqual(
                controller.toolbarItems?[2].accessibilityLabel,
                String(localized: "archive.selected.category.add")
            )
            XCTAssertEqual(controller.toolbarItems?[2].isEnabled, false)
            XCTAssertEqual(controller.toolbarItems?[2].menu?.children.map(\.title), [])
        }
        XCTAssertEqual(controller.toolbarItems?[3].isEnabled, true)
        XCTAssertEqual(controller.toolbarItems?[4].isEnabled, true)
        store.send(.toggleSelectionMode)
        await Task.yield()
        XCTAssertTrue(navigation.isToolbarHidden)
        if #available(iOS 18.0, *) { XCTAssertEqual(tabs.isTabBarHidden, pushed) }
        XCTAssertFalse(controller.navigationItem.hidesBackButton)
        XCTAssertEqual(navigation.viewControllers.count, pushed ? 2 : 1)
    }
}
