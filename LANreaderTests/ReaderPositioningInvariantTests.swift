import XCTest
@testable import LANreader

final class ReaderPositioningInvariantTests: LANreaderTestCase {
    func testInitialPageIndexMatrix() {
        // Saved progress is a one-based page number. Spreads are paired around the result later, when
        // the reader decides its layout.
        let cases: [InitialPageCase] = [
            .init("empty archive", 0, 0, false, false, 0),
            .init("no progress yet", 0, 5, false, false, 0),
            .init("negative progress", -3, 5, false, false, 0),
            .init("saved page", 3, 5, false, false, 2),
            .init("progress beyond last page", 99, 5, false, false, 4),
            .init("from start", 5, 5, true, false, 0),
            .init("finished archive restarts", 6, 6, false, true, 0)
        ]

        for testCase in cases {
            XCTAssertEqual(
                ReaderPositioning.initialPageIndex(
                    progress: testCase.progress,
                    pageCount: testCase.pageCount,
                    fromStart: testCase.fromStart,
                    restartFinishedArchive: testCase.restartFinishedArchive
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
        for readDirection in ReadDirection.allCases {
            for doublePageLayout in [false, true] {
                for direction in [ReaderNavigationDirection.next, .previous] {
                    XCTAssertNil(ReaderPositioning.adjacentPageIndex(
                        from: 0, direction: direction, pageCount: 0,
                        readDirection: readDirection, doublePageLayout: doublePageLayout
                    ), "empty archive")
                }
            }
        }
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
                fromStart: false
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
    let expected: Int

    init(
        _ name: String,
        _ progress: Int,
        _ pageCount: Int,
        _ fromStart: Bool,
        _ restartFinishedArchive: Bool,
        _ expected: Int
    ) {
        self.name = name
        self.progress = progress
        self.pageCount = pageCount
        self.fromStart = fromStart
        self.restartFinishedArchive = restartFinishedArchive
        self.expected = expected
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
