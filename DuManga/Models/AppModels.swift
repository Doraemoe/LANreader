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
}
