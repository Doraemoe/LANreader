import ComposableArchitecture
import Foundation

enum ReaderLayoutCoordinator {
    struct LayoutJump: Equatable, Sendable {
        let targetPageIndex: Int
        let source: ReaderNavigationSource
    }

    static func applyPrimedAspectRatios(
        _ aspectRatios: [Int: Double],
        state: inout ArchiveReaderFeature.State
    ) {
        for pageId in state.pages.ids {
            guard let page = state.pages[id: pageId], page.imageAspectRatio == nil else { continue }
            guard let aspectRatio = aspectRatios[page.pageNumber] else { continue }
            state.pages[id: pageId]?.imageAspectRatio = aspectRatio
        }
        updateEstimatedPageAspectRatio(state: &state)
    }

    static func updateEstimatedPageAspectRatio(state: inout ArchiveReaderFeature.State) {
        guard let median = ReaderPageLayout.medianAspectRatio(state.pages.compactMap(\.imageAspectRatio)) else {
            return
        }
        guard state.estimatedPageAspectRatio != median else { return }
        state.estimatedPageAspectRatio = median
    }

    static func resolvedDoublePageLayout(state: ArchiveReaderFeature.State) -> Bool {
        guard state.resolvedReadDirection != .upDown, !state.splitImage else { return false }
        guard state.automaticPageLayout else { return state.manualDoublePageLayout }
        return state.pages.count > 1 && ReaderPageLayout.automaticDoublePageLayout(
            readerSize: state.readerSize, currentlyEnabled: state.doublePageLayout
        )
    }

    static func restoreInitialPage(
        progress: Int,
        restartFinishedArchive: Bool,
        state: inout ArchiveReaderFeature.State
    ) {
        let storedIndex = ReaderPositioning.initialPageIndex(
            progress: progress,
            pageCount: state.pages.count,
            fromStart: state.fromStart,
            restartFinishedArchive: restartFinishedArchive
        )
        let enabled = resolvedDoublePageLayout(state: state)
        state.doublePageLayout = false
        state.spreadPairingOffset = 0
        state.spreadAnchorPageIndex = nil
        state.currentPageIndex = enabled
            ? applyPageLayout(true, pageIndex: storedIndex, restoring: true, state: &state)
            : storedIndex
    }

    static func updatePageLayout(state: inout ArchiveReaderFeature.State) -> LayoutJump? {
        guard !state.pages.isEmpty else { return nil }
        let enabled = resolvedDoublePageLayout(state: state)
        guard enabled != state.doublePageLayout else { return nil }
        let restoring = state.scrollRequest?.source == .initialRestore
        // A pending initial restore or slider jump has priority over the last reported visible page.
        let pageIndex = state.scrollRequest?.targetPageIndex ?? state.currentPageIndex
        let targetIndex = applyPageLayout(enabled, pageIndex: pageIndex, restoring: restoring, state: &state)
        return LayoutJump(
            targetPageIndex: targetIndex,
            source: restoring ? .initialRestore : .layoutChange
        )
    }

    /// Saved progress is the trailing page of a spread, so a restored page is paired with the page
    /// before it, while any other page starts its spread. Turning spreads off returns to the page the
    /// spread was built around while it is still on screen, or else to the spread's first page.
    static func applyPageLayout(
        _ enabled: Bool,
        pageIndex: Int,
        restoring: Bool,
        state: inout ArchiveReaderFeature.State
    ) -> Int {
        let pageCount = state.pages.count
        let readDirection = state.resolvedReadDirection
        let previousOffset = state.spreadPairingOffset
        let anchorIndex = state.spreadAnchorPageIndex
        state.doublePageLayout = enabled
        guard enabled else {
            state.spreadPairingOffset = 0
            state.spreadAnchorPageIndex = nil
            let spreadStart = ReaderPositioning.scrollAnchorIndex(
                forPageIndex: pageIndex, pageCount: pageCount, readDirection: readDirection,
                doublePageLayout: true, spreadOffset: previousOffset
            )
            let spreadEnd = ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: pageIndex, pageCount: pageCount, readDirection: readDirection,
                doublePageLayout: true, spreadOffset: previousOffset
            )
            if let anchorIndex, (spreadStart...max(spreadStart, spreadEnd)).contains(anchorIndex) {
                return anchorIndex
            }
            return spreadStart
        }
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: pageCount)
        state.spreadPairingOffset = restoring && clampedIndex > 0 ? (clampedIndex + 1) % 2 : clampedIndex % 2
        state.spreadAnchorPageIndex = clampedIndex
        return ReaderPositioning.canonicalPageIndex(
            forVisibleIndex: clampedIndex, pageCount: pageCount, readDirection: readDirection,
            doublePageLayout: true, spreadOffset: state.spreadPairingOffset
        )
    }
}
