//
// Created on 13/9/20.
//

import Foundation

struct ArchiveState {
    @PublishedState var loading = false
    @PublishedState var archiveItems = [String: ArchiveItem]()
    @PublishedState var dynamicCategoryKeys = [String]()
    @PublishedState var updateArchiveMetadataSuccess = false
    @PublishedState var errorCode: ErrorCode?
}
