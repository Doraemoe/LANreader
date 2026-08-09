import Foundation

/// Pure page-arithmetic for the archive list pager. Pages are zero-based internally and
/// displayed one-based; the server is addressed by item offset, never by page number.
enum PaginationPositioning {
    static func pageCount(total: Int, pageSize: Int) -> Int {
        guard total > 0, pageSize > 0 else { return 0 }
        return (total - 1) / pageSize + 1
    }

    static func clampedPage(_ page: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(page, 0), pageCount - 1)
    }

    /// Item offset to send as the LANraragi `start` parameter for a given page.
    static func itemOffset(page: Int, pageSize: Int) -> Int {
        guard pageSize > 0 else { return 0 }
        return max(page, 0) * pageSize
    }
}
