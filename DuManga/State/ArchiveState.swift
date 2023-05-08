//
// Created on 13/9/20.
//

import Foundation

struct ArchiveState {
    @PublishedState var loading = false
    @PublishedState var archiveItems = [String: ArchiveItem]()
    @PublishedState var randomOrderSeed = UInt64.random(in: 1..<10000)
    @PublishedState var errorCode: ErrorCode?
}
