//
// Created on 13/9/20.
//

import Foundation

struct ArchiveState {
    var loading: Bool
    var archiveItems: [String: ArchiveItem]
    var dynamicCategoryKeys: [String]
    var archivePages: [String: [String]]
    var updateArchiveMetadataSuccess: Bool
    var errorCode: ErrorCode?

    init() {
        self.loading = false
        self.archiveItems = [String: ArchiveItem]()
        self.dynamicCategoryKeys = [String]()
        self.archivePages = [String: [String]]()
        self.updateArchiveMetadataSuccess = false
        self.errorCode = nil
    }
}
