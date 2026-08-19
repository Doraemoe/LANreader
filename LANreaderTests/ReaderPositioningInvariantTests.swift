import XCTest
@testable import LANreader

final class ReaderPositioningInvariantTests: XCTestCase {
    func testInitialPageIndexMatrix() {
        let cases: [InitialPageCase] = [
            .init("empty archive", 0, 0, false, false, .leftRight, false, 0),
            .init("negative progress", -3, 5, false, false, .leftRight, false, 0),
            .init("progress beyond last page", 99, 5, false, false, .rightLeft, false, 4),
            .init("one-page double layout", 1, 1, false, false, .rightLeft, true, 0),
            .init("first even spread", 0, 2, false, false, .leftRight, true, 1),
            .init("middle odd spread", 3, 5, false, false, .rightLeft, true, 3),
            .init("last even spread", 6, 6, false, false, .leftRight, true, 5),
            .init("vertical reader", 3, 5, false, false, .upDown, true, 2),
            .init("from-start first spread", 5, 5, true, false, .leftRight, true, 1),
            .init("finished restart first spread", 6, 6, false, true, .rightLeft, true, 1),
            .init("shifted spread restore", 2, 5, false, false, .leftRight, true, 2, 1)
        ]

        for testCase in cases {
            XCTAssertEqual(
                ReaderPositioning.initialPageIndex(
                    progress: testCase.progress,
                    pageCount: testCase.pageCount,
                    fromStart: testCase.fromStart,
                    restartFinishedArchive: testCase.restartFinishedArchive,
                    readDirection: testCase.readDirection,
                    doublePageLayout: testCase.doublePageLayout,
                    spreadOffset: testCase.spreadOffset
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testCanonicalPageAndScrollAnchorMatrix() {
        let cases: [PageMappingCase] = [
            .init("empty archive", 0, .leftRight, false, [0], [0]),
            .init("one-page spread", 1, .rightLeft, true, [0], [0]),
            .init("two-page spread", 2, .leftRight, true, [1, 1], [0, 0]),
            .init("odd final spread", 5, .rightLeft, true, [1, 1, 3, 3, 4], [0, 0, 2, 2, 4]),
            .init("even final spread", 6, .leftRight, true, [1, 1, 3, 3, 5, 5], [0, 0, 2, 2, 4, 4]),
            .init("shifted odd spread", 5, .leftRight, true, [0, 2, 2, 4, 4], [0, 1, 1, 3, 3], 1),
            .init("shifted even spread", 6, .rightLeft, true, [0, 2, 2, 4, 4, 5], [0, 1, 1, 3, 3, 5], 1),
            .init("vertical reader", 5, .upDown, true, [0, 1, 2, 3, 4], [0, 1, 2, 3, 4]),
            .init("single-page reader", 5, .leftRight, false, [0, 1, 2, 3, 4], [0, 1, 2, 3, 4])
        ]

        for testCase in cases {
            let indices = testCase.pageCount == 0 ? [0] : Array(0..<testCase.pageCount)
            let canonicalPages = indices.map {
                ReaderPositioning.canonicalPageIndex(
                    forVisibleIndex: $0,
                    pageCount: testCase.pageCount,
                    readDirection: testCase.readDirection,
                    doublePageLayout: testCase.doublePageLayout,
                    spreadOffset: testCase.spreadOffset
                )
            }
            let scrollAnchors = canonicalPages.map {
                ReaderPositioning.scrollAnchorIndex(
                    forPageIndex: $0,
                    pageCount: testCase.pageCount,
                    readDirection: testCase.readDirection,
                    doublePageLayout: testCase.doublePageLayout,
                    spreadOffset: testCase.spreadOffset
                )
            }

            XCTAssertEqual(canonicalPages, testCase.canonicalPages, testCase.name)
            XCTAssertEqual(scrollAnchors, testCase.scrollAnchors, testCase.name)
        }
    }

    func testAdjacentNavigationMatrix() {
        let cases: [NavigationCase] = [
            .init("empty archive", 0, .leftRight, false, []),
            .init("one-page spread", 1, .rightLeft, true, [0]),
            .init("single-page reader", 5, .leftRight, false, [0, 1, 2, 3, 4]),
            .init("vertical reader", 5, .upDown, true, [0, 1, 2, 3, 4]),
            .init("odd spread reader", 5, .leftRight, true, [1, 3, 4]),
            .init("even spread reader", 6, .rightLeft, true, [1, 3, 5]),
            .init("shifted odd spread reader", 5, .leftRight, true, [0, 2, 4], 1),
            .init("shifted even spread reader", 6, .rightLeft, true, [0, 2, 4, 5], 1)
        ]

        for testCase in cases {
            guard !testCase.canonicalPages.isEmpty else {
                XCTAssertNil(adjacentPageIndex(in: testCase, from: 0, direction: .next), testCase.name)
                XCTAssertNil(adjacentPageIndex(in: testCase, from: 0, direction: .previous), testCase.name)
                continue
            }
            assertAdjacentNavigation(in: testCase)
        }
    }

    func testHorizontalReadingDirectionsShareLogicalPositioning() {
        for pageCount in 0...8 {
            for doublePageLayout in [false, true] {
                for spreadOffset in 0...1 {
                    for pageIndex in -1...pageCount {
                        let context = "pages=\(pageCount), index=\(pageIndex), "
                            + "double=\(doublePageLayout), offset=\(spreadOffset)"
                        XCTAssertEqual(
                            positioningSnapshot(
                                pageIndex: pageIndex,
                                pageCount: pageCount,
                                readDirection: .leftRight,
                                doublePageLayout: doublePageLayout,
                                spreadOffset: spreadOffset
                            ),
                            positioningSnapshot(
                                pageIndex: pageIndex,
                                pageCount: pageCount,
                                readDirection: .rightLeft,
                                doublePageLayout: doublePageLayout,
                                spreadOffset: spreadOffset
                            ),
                            context
                        )
                    }
                }
            }
        }
    }

    func testVerticalReaderIgnoresDoublePageLayout() {
        for pageCount in 0...8 {
            for spreadOffset in 0...1 {
                for pageIndex in -1...pageCount {
                    let context = "pages=\(pageCount), index=\(pageIndex), offset=\(spreadOffset)"
                    XCTAssertEqual(
                        positioningSnapshot(
                            pageIndex: pageIndex,
                            pageCount: pageCount,
                            readDirection: .upDown,
                            doublePageLayout: false,
                            spreadOffset: spreadOffset
                        ),
                        positioningSnapshot(
                            pageIndex: pageIndex,
                            pageCount: pageCount,
                            readDirection: .upDown,
                            doublePageLayout: true,
                            spreadOffset: spreadOffset
                        ),
                        context
                    )
                }
            }
        }
    }

    func testPositioningAlgebraAcrossPageCounts() {
        for pageCount in 1...100 {
            for readDirection in ReadDirection.allCases {
                for doublePageLayout in [false, true] {
                    for spreadOffset in 0...1 {
                        assertPositioningAlgebra(
                            in: PositioningAlgebraCase(
                                pageCount: pageCount,
                                readDirection: readDirection,
                                doublePageLayout: doublePageLayout,
                                spreadOffset: spreadOffset
                            )
                        )
                    }
                }
            }
        }
    }

    private func assertPositioningAlgebra(in testCase: PositioningAlgebraCase) {
        let canonicalPages = Array(Set((0..<testCase.pageCount).map {
            ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: $0,
                pageCount: testCase.pageCount,
                readDirection: testCase.readDirection,
                doublePageLayout: testCase.doublePageLayout,
                spreadOffset: testCase.spreadOffset
            )
        })).sorted()

        XCTAssertTrue(
            canonicalPages.allSatisfy { (0..<testCase.pageCount).contains($0) },
            testCase.context
        )
        for (offset, canonicalPage) in canonicalPages.enumerated() {
            let scrollAnchor = ReaderPositioning.scrollAnchorIndex(
                forPageIndex: canonicalPage,
                pageCount: testCase.pageCount,
                readDirection: testCase.readDirection,
                doublePageLayout: testCase.doublePageLayout,
                spreadOffset: testCase.spreadOffset
            )
            XCTAssertEqual(
                ReaderPositioning.canonicalPageIndex(
                    forVisibleIndex: scrollAnchor,
                    pageCount: testCase.pageCount,
                    readDirection: testCase.readDirection,
                    doublePageLayout: testCase.doublePageLayout,
                    spreadOffset: testCase.spreadOffset
                ),
                canonicalPage,
                testCase.context
            )
            assertPositioningAdjacency(
                from: canonicalPage,
                at: offset,
                in: canonicalPages,
                testCase: testCase
            )
        }
    }

    private func assertPositioningAdjacency(
        from canonicalPage: Int,
        at offset: Int,
        in canonicalPages: [Int],
        testCase: PositioningAlgebraCase
    ) {
        let previous = offset > 0 ? canonicalPages[offset - 1] : nil
        let next = offset < canonicalPages.count - 1 ? canonicalPages[offset + 1] : nil
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: canonicalPage,
                direction: .previous,
                pageCount: testCase.pageCount,
                readDirection: testCase.readDirection,
                doublePageLayout: testCase.doublePageLayout,
                spreadOffset: testCase.spreadOffset
            ),
            previous,
            testCase.context
        )
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: canonicalPage,
                direction: .next,
                pageCount: testCase.pageCount,
                readDirection: testCase.readDirection,
                doublePageLayout: testCase.doublePageLayout,
                spreadOffset: testCase.spreadOffset
            ),
            next,
            testCase.context
        )
    }

    private func assertAdjacentNavigation(in testCase: NavigationCase) {
        for (offset, pageIndex) in testCase.canonicalPages.enumerated() {
            let previous = offset > 0 ? testCase.canonicalPages[offset - 1] : nil
            let next = offset < testCase.canonicalPages.count - 1
                ? testCase.canonicalPages[offset + 1]
                : nil

            XCTAssertEqual(
                adjacentPageIndex(in: testCase, from: pageIndex, direction: .previous),
                previous,
                "\(testCase.name), previous from \(pageIndex)"
            )
            XCTAssertEqual(
                adjacentPageIndex(in: testCase, from: pageIndex, direction: .next),
                next,
                "\(testCase.name), next from \(pageIndex)"
            )
        }
    }

    private func adjacentPageIndex(
        in testCase: NavigationCase,
        from pageIndex: Int,
        direction: ReaderNavigationDirection
    ) -> Int? {
        ReaderPositioning.adjacentPageIndex(
            from: pageIndex,
            direction: direction,
            pageCount: testCase.pageCount,
            readDirection: testCase.readDirection,
            doublePageLayout: testCase.doublePageLayout,
            spreadOffset: testCase.spreadOffset
        )
    }

    private func positioningSnapshot(
        pageIndex: Int,
        pageCount: Int,
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadOffset: Int = 0
    ) -> PositioningSnapshot {
        PositioningSnapshot(
            initialPage: ReaderPositioning.initialPageIndex(
                progress: pageIndex + 1,
                pageCount: pageCount,
                fromStart: false,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            ),
            canonicalPage: ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: pageIndex,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            ),
            scrollAnchor: ReaderPositioning.scrollAnchorIndex(
                forPageIndex: pageIndex,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            ),
            previousPage: ReaderPositioning.adjacentPageIndex(
                from: pageIndex,
                direction: .previous,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            ),
            nextPage: ReaderPositioning.adjacentPageIndex(
                from: pageIndex,
                direction: .next,
                pageCount: pageCount,
                readDirection: readDirection,
                doublePageLayout: doublePageLayout,
                spreadOffset: spreadOffset
            )
        )
    }
}

private struct InitialPageCase {
    let name: String
    let progress: Int
    let pageCount: Int
    let fromStart: Bool
    let restartFinishedArchive: Bool
    let readDirection: ReadDirection
    let doublePageLayout: Bool
    let expected: Int
    let spreadOffset: Int

    init(
        _ name: String,
        _ progress: Int,
        _ pageCount: Int,
        _ fromStart: Bool,
        _ restartFinishedArchive: Bool,
        _ readDirection: ReadDirection,
        _ doublePageLayout: Bool,
        _ expected: Int,
        _ spreadOffset: Int = 0
    ) {
        self.name = name
        self.progress = progress
        self.pageCount = pageCount
        self.fromStart = fromStart
        self.restartFinishedArchive = restartFinishedArchive
        self.readDirection = readDirection
        self.doublePageLayout = doublePageLayout
        self.expected = expected
        self.spreadOffset = spreadOffset
    }
}

private struct PageMappingCase {
    let name: String
    let pageCount: Int
    let readDirection: ReadDirection
    let doublePageLayout: Bool
    let canonicalPages: [Int]
    let scrollAnchors: [Int]
    let spreadOffset: Int

    init(
        _ name: String,
        _ pageCount: Int,
        _ readDirection: ReadDirection,
        _ doublePageLayout: Bool,
        _ canonicalPages: [Int],
        _ scrollAnchors: [Int],
        _ spreadOffset: Int = 0
    ) {
        self.name = name
        self.pageCount = pageCount
        self.readDirection = readDirection
        self.doublePageLayout = doublePageLayout
        self.canonicalPages = canonicalPages
        self.scrollAnchors = scrollAnchors
        self.spreadOffset = spreadOffset
    }
}

private struct NavigationCase {
    let name: String
    let pageCount: Int
    let readDirection: ReadDirection
    let doublePageLayout: Bool
    let canonicalPages: [Int]
    let spreadOffset: Int

    init(
        _ name: String,
        _ pageCount: Int,
        _ readDirection: ReadDirection,
        _ doublePageLayout: Bool,
        _ canonicalPages: [Int],
        _ spreadOffset: Int = 0
    ) {
        self.name = name
        self.pageCount = pageCount
        self.readDirection = readDirection
        self.doublePageLayout = doublePageLayout
        self.canonicalPages = canonicalPages
        self.spreadOffset = spreadOffset
    }
}

private struct PositioningAlgebraCase {
    let pageCount: Int
    let readDirection: ReadDirection
    let doublePageLayout: Bool
    let spreadOffset: Int

    var context: String {
        "pages=\(pageCount), direction=\(readDirection), "
            + "double=\(doublePageLayout), offset=\(spreadOffset)"
    }
}

private struct PositioningSnapshot: Equatable {
    let initialPage: Int
    let canonicalPage: Int
    let scrollAnchor: Int
    let previousPage: Int?
    let nextPage: Int?
}
