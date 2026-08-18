import Foundation

public enum ReaderNavigationSource: Equatable, Sendable {
    case initialRestore
    case slider
    case chapter
    case tap
    case keyboard
    case autoPage
    case layoutChange

    /// Repositioning after a restore, an explicit jump, or a layout change should land instantly,
    /// while page-by-page navigation animates.
    var usesAnimatedScroll: Bool {
        switch self {
        case .initialRestore, .slider, .chapter, .layoutChange:
            return false
        case .tap, .keyboard, .autoPage:
            return true
        }
    }
}

public enum ReaderNavigationDirection: Equatable, Sendable {
    case next
    case previous
}

public struct ScrollRequest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let targetPageIndex: Int
    public let source: ReaderNavigationSource
    public let animated: Bool

    public init(
        id: UUID = UUID(),
        targetPageIndex: Int,
        source: ReaderNavigationSource,
        animated: Bool
    ) {
        self.id = id
        self.targetPageIndex = targetPageIndex
        self.source = source
        self.animated = animated
    }
}

enum ReaderPositioning {
    /// Returns true when stored progress indicates the archive was read to the end.
    /// Progress is a one-based page number, so it only counts as finished once it reaches the last page.
    static func isFinished(progress: Int, archivePageCount: Int) -> Bool {
        guard archivePageCount > 0 else { return false }
        return progress == archivePageCount
    }

    static func initialPageIndex(
        progress: Int,
        pageCount: Int,
        fromStart: Bool,
        restartFinishedArchive: Bool = false,
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadOffset: Int = 0
    ) -> Int {
        guard pageCount > 0 else { return 0 }
        let restart = fromStart || restartFinishedArchive
        let storedIndex = restart ? 0 : max(progress - 1, 0)
        let clampedIndex = clampedPageIndex(storedIndex, pageCount: pageCount)
        guard usesTrailingSpreadProgress(
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        ) else {
            return clampedIndex
        }
        return canonicalPageIndex(
            forVisibleIndex: clampedIndex,
            pageCount: pageCount,
            readDirection: readDirection,
            doublePageLayout: doublePageLayout,
            spreadOffset: spreadOffset
        )
    }

    static func defaultStartPageIndex(
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadOffset: Int = 0
    ) -> Int {
        initialPageIndex(
            progress: 0,
            pageCount: pageCount,
            fromStart: true,
            readDirection: readDirection,
            doublePageLayout: doublePageLayout,
            spreadOffset: spreadOffset
        )
    }

    static func clampedPageIndex(_ index: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(index, 0), pageCount - 1)
    }

    /// Returns the canonical page index for a given visible item index.
    /// In double-page (spread) layout the canonical index is the later logical page of the spread,
    /// e.g. visible index 0 maps to canonical index 1 for spread [0, 1]. A one-item spread offset
    /// shifts the sequence to [blank, 0], [1, 2], [3, 4], and so on.
    /// In single-page or vertical layout the canonical index equals the visible index.
    static func canonicalPageIndex(
        forVisibleIndex visibleIndex: Int,
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadOffset: Int = 0
    ) -> Int {
        let clampedIndex = clampedPageIndex(visibleIndex, pageCount: pageCount)
        guard usesTrailingSpreadProgress(
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        ) else {
            return clampedIndex
        }

        let normalizedOffset = normalizedSpreadOffset(spreadOffset)
        let spreadStart = ((clampedIndex + normalizedOffset) / 2) * 2 - normalizedOffset
        return clampedPageIndex(spreadStart + 1, pageCount: pageCount)
    }

    static func scrollAnchorIndex(
        forPageIndex pageIndex: Int,
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadOffset: Int = 0
    ) -> Int {
        let clampedIndex = clampedPageIndex(pageIndex, pageCount: pageCount)
        guard usesTrailingSpreadProgress(
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        ) else {
            return clampedIndex
        }

        let normalizedOffset = normalizedSpreadOffset(spreadOffset)
        let spreadStart = ((clampedIndex + normalizedOffset) / 2) * 2 - normalizedOffset
        return max(0, spreadStart)
    }

    static func adjacentPageIndex(
        from currentPageIndex: Int,
        direction: ReaderNavigationDirection,
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadOffset: Int = 0
    ) -> Int? {
        guard pageCount > 0 else { return nil }
        let currentIndex = clampedPageIndex(currentPageIndex, pageCount: pageCount)
        if usesTrailingSpreadProgress(
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        ) {
            let currentCanonicalIndex = canonicalPageIndex(
                forVisibleIndex: currentIndex,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            )
            let currentAnchor = scrollAnchorIndex(
                forPageIndex: currentCanonicalIndex,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            )
            let targetAnchor: Int
            switch direction {
            case .next:
                targetAnchor = currentAnchor + 2
            case .previous:
                targetAnchor = currentAnchor - 2
            }

            let clampedAnchor = clampedPageIndex(targetAnchor, pageCount: pageCount)
            let targetIndex = canonicalPageIndex(
                forVisibleIndex: clampedAnchor,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            )
            guard targetIndex != currentCanonicalIndex else { return nil }
            return targetIndex
        }

        let targetIndex: Int
        switch direction {
        case .next:
            targetIndex = currentIndex + 1
        case .previous:
            targetIndex = currentIndex - 1
        }

        let clampedTarget = clampedPageIndex(targetIndex, pageCount: pageCount)
        guard clampedTarget != currentIndex else { return nil }
        return clampedTarget
    }

    static func firstVisualPageIndex(
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadOffset: Int = 0
    ) -> Int {
        canonicalPageIndex(
            forVisibleIndex: 0,
            pageCount: pageCount,
            readDirection: readDirection,
            doublePageLayout: doublePageLayout,
            spreadOffset: spreadOffset
        )
    }

    private static func normalizedSpreadOffset(_ spreadOffset: Int) -> Int {
        min(max(spreadOffset, 0), 1)
    }

    private static func usesTrailingSpreadProgress(
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> Bool {
        readDirection != .upDown && doublePageLayout
    }
}
