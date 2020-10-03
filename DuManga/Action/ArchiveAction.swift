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

    case fetchArchiveThumbnail(id: String)
    case replaceArchiveThumbnail(id: String, image: Image)

    case updateArchiveMetadata(metadata: ArchiveItem)
    case updateArchiveMetadataSuccess(metadata: ArchiveItem)

    case error(error: ErrorCode)
    case resetState
}
