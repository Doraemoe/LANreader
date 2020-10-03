//
// Created on 3/10/20.
//

import Foundation
import SwiftUI

enum PageAction {
    case extractArchive(id: String)
    case extractArchiveSuccess(id: String, pages: [String])

    case error(error: ErrorCode)
    case resetState
}
