//
// Created on 13/9/20.
//

import Foundation
import SwiftUI

enum ArchiveAction {
    case fetchArchive
    case fetchArchiveSuccess(archive: [String: ArchiveItem])

    case fetchArchiveDynamicCategory(keyword: String)
    case fetchArchiveDynamicCategorySuccess(keys: [String])

    case updateArchiveMetadata(metadata: ArchiveItem)
    case updateArchiveMetadataSuccess(metadata: ArchiveItem)

    case updateReadProgressServer(id: String, progress: Int)
    case updateReadProgressLocal(id: String, progress: Int)

    case error(error: ErrorCode)
    case resetState
}
