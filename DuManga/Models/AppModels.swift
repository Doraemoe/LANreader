//
// Created on 10/9/20.
//

import Foundation

struct ErrorCode {
    let name: String
    let code: Int

    private init(name:String, code:Int) {
        self.name = name
        self.code = code
    }

    static let lanraragiServerError = ErrorCode(name: "error.host", code: 1000)
    static let categoryFetchError = ErrorCode(name: "error.category", code: 2000)
    static let categoryUpdateError = ErrorCode(name: "error.category.update", code: 2001)
}
