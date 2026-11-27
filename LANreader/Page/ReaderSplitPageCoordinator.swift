import ComposableArchitecture
import Foundation

enum ReaderSplitPageCoordinator {
    static func preparePendingSplitMode(
        state: inout ArchiveReaderFeature.State,
        pageIndex: Int
    ) {
        guard state.splitImage else { return }
        guard state.pages.indices.contains(pageIndex) else { return }
        guard state.pages[pageIndex].pageMode == .loading else { return }

        state.pages[pageIndex].pendingSplitMode = if pageIndex < state.currentPageIndex {
            PageMode.trailingSplitMode(priorityLeft: state.piorityLeft)
        } else {
            PageMode.preferredSplitMode(priorityLeft: state.piorityLeft)
        }
    }

    static func handleSplitResolution(
        id: PageFeature.State.ID,
        shouldDisplayAsSplitPages: Bool,
        state: inout ArchiveReaderFeature.State
    ) {
        guard state.pages[id: id] != nil else { return }
        if state.collectionScrolling {
            state.pendingSplitResolutions[id] = shouldDisplayAsSplitPages
            return
        }

        applySplitResolution(
            id: id,
            shouldDisplayAsSplitPages: shouldDisplayAsSplitPages,
            state: &state
        )
    }

    static func applyPendingSplitResolutions(state: inout ArchiveReaderFeature.State) {
        let pending = state.pendingSplitResolutions
        state.pendingSplitResolutions = [:]

        for pageId in state.pages.map(\.id) where pending[pageId] != nil {
            applySplitResolution(
                id: pageId,
                shouldDisplayAsSplitPages: pending[pageId] ?? false,
                state: &state
            )
        }
    }

    static func setSplitSiblingsLoaded(
        _ loaded: Bool,
        id: PageFeature.State.ID,
        state: inout ArchiveReaderFeature.State
    ) {
        guard let page = state.pages[id: id] else { return }
        let siblingIds = state.pages
            .filter { $0.pageId == page.pageId && $0.id != id && $0.pageMode.isSplitMode }
            .map(\.id)
        for siblingId in siblingIds {
            state.pages[id: siblingId]?.imageLoaded = loaded
        }
    }

    private static func applySplitResolution(
        id: PageFeature.State.ID,
        shouldDisplayAsSplitPages: Bool,
        state: inout ArchiveReaderFeature.State
    ) {
        let visiblePageId = state.currentPage?.id

        guard shouldDisplayAsSplitPages,
              state.splitImage else {
            normalizePageDisplay(id: id, state: &state)
            preserveVisiblePage(id: visiblePageId, state: &state)
            return
        }

        applySplitPageDisplay(id: id, state: &state)
        preserveVisiblePage(id: visiblePageId, state: &state)
    }

    private static func applySplitPageDisplay(
        id: PageFeature.State.ID,
        state: inout ArchiveReaderFeature.State
    ) {
        guard let current = state.pages[id: id],
              let sourcePageIndex = state.pages.index(id: id) else {
            return
        }

        let splitMode: PageMode
        if current.pageMode.isSplitMode {
            splitMode = current.pageMode
        } else {
            splitMode = current.pendingSplitMode
                ?? PageMode.preferredSplitMode(priorityLeft: state.piorityLeft)
        }

        state.pages[id: id]?.pageMode = splitMode
        state.pages[id: id]?.pendingSplitMode = nil
        state.pages[id: id]?.imageLoaded = true

        insertSplitSibling(
            for: current,
            sourceId: id,
            sourcePageIndex: sourcePageIndex,
            splitMode: splitMode,
            state: &state
        )
    }

    private static func insertSplitSibling(
        for current: PageFeature.State,
        sourceId: PageFeature.State.ID,
        sourcePageIndex: Int,
        splitMode: PageMode,
        state: inout ArchiveReaderFeature.State
    ) {
        guard let siblingMode = splitMode.splitSiblingMode else { return }
        var insertedPage = PageFeature.State(
            archiveId: state.currentArchiveId,
            pageId: current.pageId,
            pageNumber: current.pageNumber,
            sourceArchiveId: current.sourceArchiveId,
            sourcePageNumber: current.sourcePageNumber,
            pageMode: siblingMode,
            cached: current.cached
        )
        insertedPage.imageLoaded = true
        insertedPage.imageAspectRatio = current.imageAspectRatio
        insertedPage.storedImageURL = current.storedImageURL
        // Match by half, not id: the original item keeps its normal id while showing a split half.
        if let existingSiblingId = state.pages.first(where: {
            $0.pageId == current.pageId && $0.id != sourceId && $0.pageMode == siblingMode
        })?.id {
            state.pages[id: existingSiblingId]?.storedImageURL = current.storedImageURL
            state.pages[id: existingSiblingId]?.imageLoaded = true
            return
        }
        guard state.pages[id: insertedPage.id] == nil else { return }

        let leadingSplitMode = PageMode.preferredSplitMode(priorityLeft: state.piorityLeft)
        let insertAfterCurrent = splitMode == leadingSplitMode
        let insertedIndex = insertAfterCurrent ? sourcePageIndex + 1 : sourcePageIndex
        state.pages.insert(insertedPage, at: insertedIndex)
    }

    private static func normalizePageDisplay(
        id: PageFeature.State.ID,
        state: inout ArchiveReaderFeature.State
    ) {
        guard let current = state.pages[id: id] else { return }
        let canonicalId = "\(current.pageId)-\(PageMode.normal.identitySuffix)"
        let keepId = state.pages[id: canonicalId] == nil ? id : canonicalId

        state.pages[id: keepId]?.pageMode = .normal
        state.pages[id: keepId]?.pendingSplitMode = nil
        state.pages[id: keepId]?.imageLoaded = true
        if let imageAspectRatio = current.imageAspectRatio {
            state.pages[id: keepId]?.imageAspectRatio = imageAspectRatio
        }
        if let storedImageURL = current.storedImageURL {
            state.pages[id: keepId]?.storedImageURL = storedImageURL
        }

        state.pages.removeAll {
            $0.pageId == current.pageId && $0.id != keepId
        }
    }

    private static func preserveVisiblePage(
        id visiblePageId: PageFeature.State.ID?,
        state: inout ArchiveReaderFeature.State
    ) {
        if let visiblePageId,
           let preservedIndex = state.pages.index(id: visiblePageId) {
            state.currentPageIndex = preservedIndex
        } else {
            state.currentPageIndex = ReaderPositioning.clampedPageIndex(
                state.currentPageIndex,
                pageCount: state.pages.count
            )
        }
    }
}
