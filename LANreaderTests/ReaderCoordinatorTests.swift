import ComposableArchitecture
import XCTest
@testable import LANreader

final class ReaderCoordinatorTests: LANreaderTestCase {
    func testPreparePendingSplitModeUsesDirectionAndPriorityLeftAndSkipsLoadedOrDisabled() {
        var forwardState = makeReaderState(pageCount: 3, currentPageIndex: 1, splitImage: true, priorityLeft: false)
        ReaderSplitPageCoordinator.preparePendingSplitMode(state: &forwardState, pageIndex: 2)
        XCTAssertEqual(forwardState.pages[2].pendingSplitMode, .right)

        var backwardState = makeReaderState(pageCount: 3, currentPageIndex: 2, splitImage: true, priorityLeft: false)
        ReaderSplitPageCoordinator.preparePendingSplitMode(state: &backwardState, pageIndex: 1)
        XCTAssertEqual(backwardState.pages[1].pendingSplitMode, .left)

        var priorityLeftBackward = makeReaderState(
            pageCount: 3,
            currentPageIndex: 2,
            splitImage: true,
            priorityLeft: true
        )
        ReaderSplitPageCoordinator.preparePendingSplitMode(state: &priorityLeftBackward, pageIndex: 1)
        XCTAssertEqual(priorityLeftBackward.pages[1].pendingSplitMode, .right)

        var alreadyLoaded = makeReaderState(pageCount: 3, currentPageIndex: 0, splitImage: true)
        alreadyLoaded.pages[1].pageMode = .normal
        ReaderSplitPageCoordinator.preparePendingSplitMode(state: &alreadyLoaded, pageIndex: 1)
        XCTAssertNil(alreadyLoaded.pages[1].pendingSplitMode)

        var splitDisabled = makeReaderState(pageCount: 3, currentPageIndex: 0, splitImage: false)
        ReaderSplitPageCoordinator.preparePendingSplitMode(state: &splitDisabled, pageIndex: 1)
        XCTAssertNil(splitDisabled.pages[1].pendingSplitMode)
    }

    func testHandleSplitResolutionDefersDuringScrollAndAppliesInPageOrderPreservingCurrentPage() {
        var state = makeReaderState(pageCount: 4, currentPageIndex: 2, splitImage: true)
        state.collectionScrolling = true
        let firstId = state.pages[0].id
        let thirdId = state.pages[2].id

        ReaderSplitPageCoordinator.handleSplitResolution(id: firstId, shouldDisplayAsSplitPages: true, state: &state)
        XCTAssertEqual(state.pages.count, 4)
        XCTAssertEqual(state.pendingSplitResolutions, [firstId: true])

        state.collectionScrolling = false
        ReaderSplitPageCoordinator.applyPendingSplitResolutions(state: &state)

        XCTAssertTrue(state.pendingSplitResolutions.isEmpty)
        XCTAssertEqual(state.pages.count, 5)
        XCTAssertEqual(state.pages[0].pageMode, .right)
        XCTAssertEqual(state.pages[1].pageMode, .left)
        XCTAssertEqual(state.currentPageIndex, 3)
        XCTAssertEqual(state.currentPage?.id, thirdId)
    }

    func testHandleSplitResolutionUpdatesExistingSiblingWithoutDuplicating() {
        var state = makeReaderState(pageCount: 1, splitImage: true)
        let originalId = state.pages[0].id
        let refreshedURL = URL(fileURLWithPath: "/tmp/archive/refreshed-1.jpg")
        state.pages[0].pageMode = .right
        state.pages[0].storedImageURL = refreshedURL
        var sibling = makePage(archiveId: "archive", pageNumber: 1, pageMode: .left)
        sibling.imageLoaded = false
        state.pages.append(sibling)

        ReaderSplitPageCoordinator.handleSplitResolution(
            id: originalId,
            shouldDisplayAsSplitPages: true,
            state: &state
        )

        XCTAssertEqual(state.pages.count, 2)
        XCTAssertEqual(state.pages[id: sibling.id]?.storedImageURL, refreshedURL)
        XCTAssertEqual(state.pages[id: sibling.id]?.imageLoaded, true)
    }

    func testHandleSplitResolutionNormalizesSplitPairWhenNoLongerWide() {
        var state = makeReaderState(pageCount: 2, currentPageIndex: 1, splitImage: true)
        let firstId = state.pages[0].id
        let storedURL = URL(fileURLWithPath: "/tmp/archive/1.jpg")
        state.pages[0].pageMode = .right
        state.pages[0].imageLoaded = true
        state.pages[0].imageAspectRatio = 1.6
        state.pages[0].storedImageURL = storedURL
        var sibling = makePage(archiveId: "archive", pageNumber: 1, pageMode: .left)
        sibling.imageAspectRatio = 1.6
        sibling.storedImageURL = storedURL
        state.pages.insert(sibling, at: 1)
        state.currentPageIndex = 2

        ReaderSplitPageCoordinator.handleSplitResolution(
            id: sibling.id,
            shouldDisplayAsSplitPages: false,
            state: &state
        )

        XCTAssertEqual(state.pages.map(\.id), [firstId, "2-normal"])
        XCTAssertEqual(state.pages[id: firstId]?.pageMode, .normal)
        XCTAssertEqual(state.pages[id: firstId]?.imageAspectRatio, 1.6)
        XCTAssertEqual(state.pages[id: firstId]?.storedImageURL, storedURL)
        XCTAssertEqual(state.currentPageIndex, 1)
    }

    func testSetSplitSiblingsLoadedOnlyUpdatesMatchingSplitSiblings() {
        var state = makeReaderState(pageCount: 2, splitImage: true)
        var leading = makePage(archiveId: "archive", pageNumber: 1, pageMode: .right)
        leading.imageLoaded = true
        var trailing = makePage(archiveId: "archive", pageNumber: 1, pageMode: .left)
        trailing.imageLoaded = true
        var unrelated = makePage(archiveId: "archive", pageNumber: 2, pageMode: .normal)
        unrelated.imageLoaded = true
        state.pages = [leading, trailing, unrelated]

        ReaderSplitPageCoordinator.setSplitSiblingsLoaded(false, id: leading.id, state: &state)
        XCTAssertEqual(state.pages[id: leading.id]?.imageLoaded, true)
        XCTAssertEqual(state.pages[id: trailing.id]?.imageLoaded, false)
        XCTAssertEqual(state.pages[id: unrelated.id]?.imageLoaded, true)

        ReaderSplitPageCoordinator.setSplitSiblingsLoaded(true, id: leading.id, state: &state)
        XCTAssertEqual(state.pages[id: trailing.id]?.imageLoaded, true)
    }

    func testApplyPrimedAspectRatiosFillsOnlyUnmeasuredPagesAndUpdatesMedian() {
        var state = makeReaderState(pageCount: 3)
        state.pages[0].imageAspectRatio = 2.0

        ReaderLayoutCoordinator.applyPrimedAspectRatios([1: 1.1, 2: 1.4, 3: 1.8], state: &state)

        XCTAssertEqual(state.pages[0].imageAspectRatio, 2.0)
        XCTAssertEqual(state.pages[1].imageAspectRatio, 1.4)
        XCTAssertEqual(state.pages[2].imageAspectRatio, 1.8)
        XCTAssertEqual(state.estimatedPageAspectRatio, 1.8)
    }

    func testRestoreInitialPagePairsSavedProgressInDoublePageLayoutAndRespectsRestart() {
        var manualState = makeReaderState(pageCount: 5, manualDoublePageLayout: true)
        ReaderLayoutCoordinator.restoreInitialPage(progress: 3, restartFinishedArchive: false, state: &manualState)
        XCTAssertTrue(manualState.doublePageLayout)
        XCTAssertEqual(manualState.spreadPairingOffset, 1)
        XCTAssertEqual(manualState.spreadAnchorPageIndex, 2)
        XCTAssertEqual(manualState.currentPageIndex, 2)

        var automaticWideState = makeReaderState(
            pageCount: 5,
            automaticPageLayout: true,
            readerSize: CGSize(width: 1_194, height: 834)
        )
        ReaderLayoutCoordinator.restoreInitialPage(
            progress: 5,
            restartFinishedArchive: true,
            state: &automaticWideState
        )
        XCTAssertTrue(automaticWideState.doublePageLayout)
        XCTAssertEqual(automaticWideState.spreadPairingOffset, 0)
        XCTAssertEqual(automaticWideState.spreadAnchorPageIndex, 0)
        XCTAssertEqual(automaticWideState.currentPageIndex, 1)
    }

    func testUpdatePageLayoutPrioritizesPendingInitialRestoreAndSkipsWhenUnchangedOrEmpty() {
        var emptyState = makeReaderState(pageCount: 0, manualDoublePageLayout: true)
        XCTAssertNil(ReaderLayoutCoordinator.updatePageLayout(state: &emptyState))

        var unchangedState = makeReaderState(pageCount: 4, doublePageLayout: false, manualDoublePageLayout: false)
        XCTAssertNil(ReaderLayoutCoordinator.updatePageLayout(state: &unchangedState))

        var restoreState = makeReaderState(
            pageCount: 6,
            currentPageIndex: 0,
            doublePageLayout: false,
            automaticPageLayout: true,
            readerSize: CGSize(width: 1_194, height: 834)
        )
        restoreState.scrollRequest = ScrollRequest(targetPageIndex: 3, source: .initialRestore, animated: false)
        let restoreJump = ReaderLayoutCoordinator.updatePageLayout(state: &restoreState)
        XCTAssertEqual(restoreJump, ReaderLayoutCoordinator.LayoutJump(targetPageIndex: 3, source: .initialRestore))
        XCTAssertTrue(restoreState.doublePageLayout)
        XCTAssertEqual(restoreState.spreadPairingOffset, 0)

        var toggleState = makeReaderState(
            pageCount: 6,
            currentPageIndex: 2,
            doublePageLayout: false,
            manualDoublePageLayout: true
        )
        let toggleJump = ReaderLayoutCoordinator.updatePageLayout(state: &toggleState)
        XCTAssertEqual(toggleJump, ReaderLayoutCoordinator.LayoutJump(targetPageIndex: 3, source: .layoutChange))
    }

    func testApplyPageLayoutDisablingSpreadReturnsAnchorWhileInSpreadOrSpreadStartOtherwise() {
        var inAnchorSpread = makeReaderState(pageCount: 6, currentPageIndex: 2, doublePageLayout: true)
        inAnchorSpread.spreadPairingOffset = 0
        inAnchorSpread.spreadAnchorPageIndex = 3
        let restoredAnchor = ReaderLayoutCoordinator.applyPageLayout(
            false,
            pageIndex: 2,
            restoring: false,
            state: &inAnchorSpread
        )
        XCTAssertEqual(restoredAnchor, 3)
        XCTAssertFalse(inAnchorSpread.doublePageLayout)
        XCTAssertEqual(inAnchorSpread.spreadPairingOffset, 0)
        XCTAssertNil(inAnchorSpread.spreadAnchorPageIndex)

        var movedSpread = makeReaderState(pageCount: 6, currentPageIndex: 4, doublePageLayout: true)
        movedSpread.spreadPairingOffset = 0
        movedSpread.spreadAnchorPageIndex = 1
        let fallbackStart = ReaderLayoutCoordinator.applyPageLayout(
            false,
            pageIndex: 4,
            restoring: false,
            state: &movedSpread
        )
        XCTAssertEqual(fallbackStart, 4)
    }
}

private func makePage(
    archiveId: String = "archive",
    pageNumber: Int,
    pageMode: PageMode = .loading
) -> PageFeature.State {
    PageFeature.State(
        archiveId: archiveId,
        pageId: "\(pageNumber)",
        pageNumber: pageNumber,
        sourceArchiveId: archiveId,
        sourcePageNumber: pageNumber,
        pageMode: pageMode
    )
}

private func makeReaderState(
    pageCount: Int,
    currentPageIndex: Int = 0,
    doublePageLayout: Bool = false,
    manualDoublePageLayout: Bool = false,
    automaticPageLayout: Bool = false,
    splitImage: Bool = false,
    priorityLeft: Bool = false,
    readerSize: CGSize = .zero
) -> ArchiveReaderFeature.State {
    var state = ArchiveReaderFeature.State(currentArchiveId: "archive", allArchives: [])
    state.$readDirection = SharedReader(value: ReadDirection.leftRight.rawValue)
    state.$splitImage = SharedReader(value: splitImage)
    state.$piorityLeft = SharedReader(value: priorityLeft)
    state.$manualDoublePageLayout = Shared(value: manualDoublePageLayout)
    state.$automaticPageLayout = Shared(value: automaticPageLayout)
    state.doublePageLayout = doublePageLayout
    state.currentPageIndex = currentPageIndex
    state.readerSize = readerSize
    state.pages = IdentifiedArray(uniqueElements: (0..<pageCount).map { index in
        makePage(pageNumber: index + 1)
    })
    return state
}
