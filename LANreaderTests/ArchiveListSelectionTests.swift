import XCTest
import ComposableArchitecture
import GRDB
import UIKit
@testable import LANreader

final class ArchiveListSelectionTests: XCTestCase {
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
            let download = try XCTUnwrap(controller.toolbarItems?.last)
            XCTAssertEqual(count.tintColor, expected)
            XCTAssertEqual(download.tintColor, expected)
        }
    }

    @MainActor
    func testLibrarySelectionControlsToolbarAndInterceptsReaderNavigation() async throws {
        var libraryState = LibraryFeature.State()
        libraryState.archiveList = makeSelectionState(count: 2)
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
    func testBatchDownloadDispatchesOnlySelectedArchivesAndExitsSelection() async throws {
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
            $0.selectMode = .inactive
            $0.selected = []
        }
        await store.finish()
    }

    @MainActor
    func testBatchCachingShowsOneSuccessAfterAllResults() async {
        var state = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil), currentTab: .library
        )
        state.cachingArchiveIds = ["a", "b", "c"]
        state.batchCachingArchiveIds = state.cachingArchiveIds
        let store = TestStore(initialState: state) { ArchiveListFeature() }
        await store.send(.cacheArchiveFinished("a")) {
            $0.cachingArchiveIds.remove("a")
            $0.batchCachingArchiveIds.remove("a")
            $0.batchCacheHadSuccess = true
        }
        await store.send(.cacheArchiveFinished("b")) {
            $0.cachingArchiveIds.remove("b")
            $0.batchCachingArchiveIds.remove("b")
        }
        await store.send(.cacheArchiveFailed("c", "Failed")) {
            $0.cachingArchiveIds = []
            $0.batchCachingArchiveIds = []
            $0.batchCacheHadSuccess = false
            $0.successMessage = String(localized: "archive.cache.added")
            $0.errorMessage = "Failed"
        }
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
