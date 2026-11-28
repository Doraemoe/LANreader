import ComposableArchitecture
import GRDB
import UIKit
import XCTest
@testable import LANreader

final class ReaderPageCollectionPeripheralTests: LANreaderTestCase {
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: SettingsKey.readDirection)
        UserDefaults.standard.removeObject(forKey: SettingsKey.doublePageLayout)
        UserDefaults.standard.removeObject(forKey: SettingsKey.automaticPageLayout)
        UserDefaults.standard.removeObject(forKey: SettingsKey.tapLeftKey)
        UserDefaults.standard.removeObject(forKey: SettingsKey.tapMiddleKey)
        UserDefaults.standard.removeObject(forKey: SettingsKey.tapRightKey)
        try await super.tearDown()
    }

    func testCollectionLayoutBuilderCollectionItemsInsertsPlaceholderOnlyForShiftedSpread() {
        let pageIds = ["p1", "p2", "p3"]

        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.collectionItems(
                pageIds: pageIds,
                readDirection: .leftRight,
                doublePageLayout: true,
                spreadPairingOffset: 1
            ),
            [.spreadPlaceholder, .page("p1"), .page("p2"), .page("p3")]
        )
        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.collectionItems(
                pageIds: pageIds,
                readDirection: .leftRight,
                doublePageLayout: true,
                spreadPairingOffset: 0
            ),
            [.page("p1"), .page("p2"), .page("p3")]
        )
        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.collectionItems(
                pageIds: pageIds,
                readDirection: .upDown,
                doublePageLayout: true,
                spreadPairingOffset: 1
            ),
            [.page("p1"), .page("p2"), .page("p3")]
        )
        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.collectionItems(
                pageIds: pageIds,
                readDirection: .rightLeft,
                doublePageLayout: false,
                spreadPairingOffset: 1
            ),
            [.page("p1"), .page("p2"), .page("p3")]
        )
    }

    func testCollectionLayoutBuilderStartOfGroupIndexPathAlignsOnlyHorizontalSpreads() {
        let oddPath = IndexPath(row: 3, section: 0)
        let evenPath = IndexPath(row: 2, section: 0)

        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.startOfGroupIndexPath(
                for: oddPath,
                readDirection: .leftRight,
                doublePageLayout: true
            ),
            IndexPath(row: 2, section: 0)
        )
        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.startOfGroupIndexPath(
                for: evenPath,
                readDirection: .rightLeft,
                doublePageLayout: true
            ),
            IndexPath(row: 2, section: 0)
        )
        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.startOfGroupIndexPath(
                for: oddPath,
                readDirection: .upDown,
                doublePageLayout: true
            ),
            oddPath
        )
        XCTAssertEqual(
            ReaderCollectionLayoutBuilder.startOfGroupIndexPath(
                for: oddPath,
                readDirection: .leftRight,
                doublePageLayout: false
            ),
            oddPath
        )
    }

    func testCollectionLayoutBuilderScrollPositionMatchesNavigationSource() {
        XCTAssertEqual(ReaderCollectionLayoutBuilder.scrollPosition(for: .initialRestore), .centeredHorizontally)
        XCTAssertEqual(ReaderCollectionLayoutBuilder.scrollPosition(for: .slider), .centeredHorizontally)
        XCTAssertEqual(ReaderCollectionLayoutBuilder.scrollPosition(for: .chapter), .left)
        XCTAssertEqual(ReaderCollectionLayoutBuilder.scrollPosition(for: .tap), .left)
        XCTAssertEqual(ReaderCollectionLayoutBuilder.scrollPosition(for: .keyboard), .left)
        XCTAssertEqual(ReaderCollectionLayoutBuilder.scrollPosition(for: .autoPage), .left)
        XCTAssertEqual(ReaderCollectionLayoutBuilder.scrollPosition(for: .layoutChange), .left)
    }

    @MainActor
    func testPullNavigationOverlaySymbolNamesAcrossDirections() {
        XCTAssertEqual(
            ReaderPullNavigationOverlay.symbolName(
                for: .previous, axis: .horizontal, isRTLReading: false, flipped: false
            ),
            "arrow.right"
        )
        XCTAssertEqual(
            ReaderPullNavigationOverlay.symbolName(
                for: .previous, axis: .horizontal, isRTLReading: false, flipped: true
            ),
            "arrow.left"
        )
        XCTAssertEqual(
            ReaderPullNavigationOverlay.symbolName(
                for: .next, axis: .horizontal, isRTLReading: true, flipped: false
            ),
            "arrow.right"
        )
        XCTAssertEqual(
            ReaderPullNavigationOverlay.symbolName(
                for: .next, axis: .horizontal, isRTLReading: true, flipped: true
            ),
            "arrow.left"
        )
        XCTAssertEqual(
            ReaderPullNavigationOverlay.symbolName(
                for: .previous, axis: .vertical, isRTLReading: false, flipped: false
            ),
            "arrow.down"
        )
        XCTAssertEqual(
            ReaderPullNavigationOverlay.symbolName(
                for: .next, axis: .vertical, isRTLReading: false, flipped: true
            ),
            "arrow.down"
        )
    }

    @MainActor
    func testPullPastThresholdAtLastPageLoadsNextArchive() async throws {
        let (store, controller) = try makeReaderController(currentPageIndex: 1)
        await waitForSnapshotApplied(on: controller, expectedCount: 2)

        let maxX = max(0, controller.collectionView.contentSize.width - controller.collectionView.bounds.width)
        controller.collectionView.contentOffset = CGPoint(x: maxX + 90, y: 0)
        controller.scrollViewDidScroll(controller.collectionView)
        controller.scrollViewDidEndDragging(controller.collectionView, willDecelerate: false)

        XCTAssertEqual(store.currentArchiveId, "arc-2")
    }

    @MainActor
    func testPullPastThresholdAtFirstArchiveBoundaryDoesNotSwitch() async throws {
        let (store, controller) = try makeReaderController(currentPageIndex: 0)
        await waitForSnapshotApplied(on: controller, expectedCount: 2)

        controller.collectionView.contentOffset = CGPoint(x: -90, y: 0)
        controller.scrollViewDidScroll(controller.collectionView)
        controller.scrollViewDidEndDragging(controller.collectionView, willDecelerate: false)

        XCTAssertEqual(store.currentArchiveId, "arc-1")
    }

    @MainActor
    func testPullBelowThresholdDoesNotSwitchArchive() async throws {
        let (store, controller) = try makeReaderController(currentPageIndex: 1)
        await waitForSnapshotApplied(on: controller, expectedCount: 2)

        let maxX = max(0, controller.collectionView.contentSize.width - controller.collectionView.bounds.width)
        controller.collectionView.contentOffset = CGPoint(x: maxX + 40, y: 0)
        controller.scrollViewDidScroll(controller.collectionView)
        controller.scrollViewDidEndDragging(controller.collectionView, willDecelerate: false)

        XCTAssertEqual(store.currentArchiveId, "arc-1")
    }

    @MainActor
    func testPullNavigationOverlayKeepsUnscaledCardBoundsAcrossProgressiveOverscroll() async throws {
        let (_, controller) = try makeReaderController(currentPageIndex: 1)
        await waitForSnapshotApplied(on: controller, expectedCount: 2)

        let card = try XCTUnwrap(
            controller.view.subviews.first { $0 is UIVisualEffectView } as? UIVisualEffectView
        )
        let maxX = max(0, controller.collectionView.contentSize.width - controller.collectionView.bounds.width)

        for (offset, expectsScaledTransform) in [(20.0, true), (50.0, true), (85.0, false)] {
            controller.collectionView.contentOffset = CGPoint(x: maxX + offset, y: 0)
            controller.scrollViewDidScroll(controller.collectionView)

            XCTAssertFalse(card.isHidden)
            XCTAssertEqual(card.bounds.origin, .zero)
            XCTAssertEqual(card.bounds.size.height, 52, accuracy: 0.01)
            XCTAssertEqual(card.transform != .identity, expectsScaledTransform)
        }
    }

    @MainActor
    func testKeyboardInputUsesConfiguredTapControls() throws {
        let suite = "ReaderPageCollectionPeripheralTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(PageControl.next.rawValue, forKey: SettingsKey.tapLeftKey)
        defaults.set(PageControl.previous.rawValue, forKey: SettingsKey.tapRightKey)

        let (store, controller) = try makeReaderController(
            pageCount: 3, currentPageIndex: 1, appStorage: defaults
        )

        XCTAssertTrue(controller.handleKeyPress(.keyboardLeftArrow))
        XCTAssertEqual(store.scrollRequest?.targetPageIndex, 0)
        XCTAssertEqual(store.scrollRequest?.source, .keyboard)

        XCTAssertTrue(controller.handleKeyPress(.keyboardRightArrow))
        XCTAssertEqual(store.scrollRequest?.targetPageIndex, 2)
        XCTAssertEqual(store.scrollRequest?.source, .keyboard)

        defaults.set(PageControl.navigation.rawValue, forKey: SettingsKey.tapLeftKey)
        let (navStore, navController) = try makeReaderController(
            pageCount: 3, currentPageIndex: 1, appStorage: defaults
        )
        let wasHidden = navStore.controlUiHidden
        XCTAssertTrue(navController.handleKeyPress(.keyboardRightArrow))
        XCTAssertEqual(navStore.controlUiHidden, !wasHidden)
        XCTAssertFalse(navController.handleKeyPress(.keyboardSpacebar))
    }

    @MainActor
    private func makeReaderController(
        pageCount: Int = 2,
        currentPageIndex: Int,
        appStorage: UserDefaults = .standard
    ) throws -> (StoreOf<ArchiveReaderFeature>, UIPageCollectionController) {
        appStorage.set(ReadDirection.leftRight.rawValue, forKey: SettingsKey.readDirection)
        appStorage.set(false, forKey: SettingsKey.doublePageLayout)
        appStorage.set(false, forKey: SettingsKey.automaticPageLayout)

        let archives = [
            makeTestArchive(id: "arc-1", pageCount: pageCount),
            makeTestArchive(id: "arc-2", pageCount: pageCount)
        ]
        let database = try AppDatabase(DatabaseQueue())
        let store = withDependencies {
            $0.defaultAppStorage = appStorage
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.appDatabase = database
        } operation: {
            var state = ArchiveReaderFeature.State(
                currentArchiveId: "arc-1",
                allArchives: archives.map { Shared(value: $0) },
                cached: true
            )
            state.pages = IdentifiedArray(
                uniqueElements: (1...pageCount).map {
                    PageFeature.State(archiveId: "arc-1", pageId: "\($0)", pageNumber: $0, cached: true)
                }
            )
            state.currentPageIndex = currentPageIndex
            return Store(initialState: state) {
                ArchiveReaderFeature()
            }
        }
        let controller = UIPageCollectionController(store: store)
        controller.loadViewIfNeeded()
        controller.collectionView.isPrefetchingEnabled = false
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        controller.view.layoutIfNeeded()
        return (store, controller)
    }

    @MainActor
    private func waitForSnapshotApplied(on controller: UIPageCollectionController, expectedCount: Int) async {
        await waitUntil {
            controller.collectionView.numberOfItems(inSection: 0) == expectedCount
                && controller.collectionView.contentSize.width >= 320
        }
    }

    private func makeTestArchive(id: String, pageCount: Int) -> ArchiveItem {
        ArchiveItem(
            id: id,
            name: id,
            extension: "zip",
            tags: "",
            isNew: false,
            progress: 0,
            pagecount: pageCount,
            dateAdded: nil,
            toc: nil
        )
    }
}
