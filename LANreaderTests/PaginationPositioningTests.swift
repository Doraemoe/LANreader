import XCTest
@testable import LANreader

final class PaginationPositioningTests: XCTestCase {
    func testPageCountRoundsUpPartialFinalPage() {
        XCTAssertEqual(PaginationPositioning.pageCount(total: 250, pageSize: 100), 3)
        XCTAssertEqual(PaginationPositioning.pageCount(total: 200, pageSize: 100), 2)
        XCTAssertEqual(PaginationPositioning.pageCount(total: 1, pageSize: 100), 1)
    }

    func testPageCountIsZeroWhenTotalOrPageSizeUnknown() {
        XCTAssertEqual(PaginationPositioning.pageCount(total: 0, pageSize: 100), 0)
        XCTAssertEqual(PaginationPositioning.pageCount(total: 50, pageSize: 0), 0)
    }

    func testItemOffsetUsesServerPageSize() {
        XCTAssertEqual(PaginationPositioning.itemOffset(page: 0, pageSize: 100), 0)
        XCTAssertEqual(PaginationPositioning.itemOffset(page: 3, pageSize: 100), 300)
        XCTAssertEqual(PaginationPositioning.itemOffset(page: 2, pageSize: 25), 50)
    }

    func testItemOffsetIsZeroWhenPageSizeUnknown() {
        XCTAssertEqual(PaginationPositioning.itemOffset(page: 4, pageSize: 0), 0)
    }

    func testClampedPageKeepsPageInsideRange() {
        XCTAssertEqual(PaginationPositioning.clampedPage(-3, pageCount: 20), 0)
        XCTAssertEqual(PaginationPositioning.clampedPage(99, pageCount: 20), 19)
        XCTAssertEqual(PaginationPositioning.clampedPage(5, pageCount: 20), 5)
        XCTAssertEqual(PaginationPositioning.clampedPage(5, pageCount: 0), 0)
    }
}
