//
// Created on 13/9/20.
//

import Foundation

struct ArchiveState {
    var loading: Bool
    var archiveItems: [String: ArchiveItem]
    var dynamicCategoryKeys: [String]
    var archivePages: [String: [String]]
    var errorCode: ErrorCode?

    init() {
        self.loading = false
        self.archiveItems = [String: ArchiveItem]()
        self.dynamicCategoryKeys = [String]()
        self.archivePages = [String: [String]]()
        self.errorCode = nil
    }
}
