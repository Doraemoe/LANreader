import Foundation

public enum ReaderNavigationSource: Equatable, Sendable {
    case initialRestore
    case slider
    case tap
    case keyboard
    case autoPage
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
    static func initialPageIndex(
        progress: Int,
        pageCount: Int,
        fromStart: Bool,
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> Int {
        guard pageCount > 0 else { return 0 }
        let storedIndex = fromStart ? 0 : max(progress - 1, 0)
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
            doublePageLayout: doublePageLayout
        )
    }

    static func defaultStartPageIndex(
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> Int {
        initialPageIndex(
            progress: 0,
            pageCount: pageCount,
            fromStart: true,
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        )
    }

    static func clampedPageIndex(_ index: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(index, 0), pageCount - 1)
    }

    /// Returns the canonical page index for a given visible item index.
    /// In double-page (spread) layout the canonical index is the trailing (right) page of the spread,
    /// e.g. visible index 0 maps to canonical index 1 for spread [0, 1].
    /// In single-page or vertical layout the canonical index equals the visible index.
    static func canonicalPageIndex(
        forVisibleIndex visibleIndex: Int,
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> Int {
        let clampedIndex = clampedPageIndex(visibleIndex, pageCount: pageCount)
        guard usesTrailingSpreadProgress(
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        ) else {
            return clampedIndex
        }

        let spreadStart = clampedIndex.isMultiple(of: 2) ? clampedIndex : clampedIndex - 1
        return min(pageCount - 1, spreadStart + 1)
    }

    static func scrollAnchorIndex(
        forPageIndex pageIndex: Int,
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> Int {
        let clampedIndex = clampedPageIndex(pageIndex, pageCount: pageCount)
        guard usesTrailingSpreadProgress(
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        ) else {
            return clampedIndex
        }

        let lastIndex = pageCount - 1
        if clampedIndex == lastIndex, lastIndex.isMultiple(of: 2) {
            return clampedIndex
        }
        return max(0, clampedIndex - 1)
    }

    static func adjacentPageIndex(
        from currentPageIndex: Int,
        direction: ReaderNavigationDirection,
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> Int? {
        guard pageCount > 0 else { return nil }
        let currentIndex = clampedPageIndex(currentPageIndex, pageCount: pageCount)
        if usesTrailingSpreadProgress(
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        ) {
            let currentAnchor = scrollAnchorIndex(
                forPageIndex: currentIndex,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout
            )
            let targetAnchor: Int
            switch direction {
            case .next:
                targetAnchor = currentAnchor + 2
            case .previous:
                targetAnchor = currentAnchor - 2
            }

            let clampedAnchor = clampedPageIndex(targetAnchor, pageCount: pageCount)
            guard clampedAnchor != currentAnchor else { return nil }
            return canonicalPageIndex(
                forVisibleIndex: clampedAnchor,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout
            )
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
        doublePageLayout: Bool
    ) -> Int {
        canonicalPageIndex(
            forVisibleIndex: 0,
            pageCount: pageCount,
            readDirection: readDirection,
            doublePageLayout: doublePageLayout
        )
    }

    private static func usesTrailingSpreadProgress(
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> Bool {
        readDirection != .upDown && doublePageLayout
    }
}
