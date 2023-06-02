//
// Created on 3/10/20.
//

import Foundation
import SwiftUI

struct PageState {
    @PublishedState var loading = false
    @PublishedState var archiveCurrentIndex = [String: Double]()
    @PublishedState var errorCode: ErrorCode?
}
