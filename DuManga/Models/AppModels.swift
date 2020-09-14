//
// Created on 10/9/20.
//

import Foundation

struct ErrorCode: Equatable {

    static func ==(lhs: ErrorCode, rhs: ErrorCode) -> Bool {
        lhs.name == rhs.name
                && lhs.code == rhs.code
    }

    let name: String
    let code: Int

    private init(name: String, code: Int) {
        self.name = name
        self.code = code
    }

    static let lanraragiServerError = ErrorCode(name: "error.host", code: 1000)

    static let archiveFetchError = ErrorCode(name: "error.list", code: 2000)
    static let archiveThumbnailError = ErrorCode(name: "error.thumbnail", code: 2001)

    static let categoryFetchError = ErrorCode(name: "error.category", code: 3000)
    static let categoryUpdateError = ErrorCode(name: "error.category.update", code: 3001)
}