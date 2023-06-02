//
// Created on 3/10/20.
//

import Foundation
import SwiftUI
import Logging

enum PageAction {
    case startExtractArchive
    case finishExtractArchive

    case error(error: ErrorCode)
    case resetState
}
