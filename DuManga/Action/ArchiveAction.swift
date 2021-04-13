//
// Created on 13/9/20.
//

import Foundation
import SwiftUI

enum ArchiveAction {
    case fetchArchive
    case fetchArchiveSuccess(archive: [String: ArchiveItem])

    case fetchArchiveDynamicCategory
    case fetchArchiveDynamicCategorySuccess

    case updateArchiveMetadata(metadata: ArchiveItem)
    case updateArchiveMetadataSuccess(metadata: ArchiveItem)

    case updateReadProgressServer(id: String, progress: Int)
    case updateReadProgressLocal(id: String, progress: Int)

    case deleteArchive(id: String)
    case deleteArchiveSuccess(id: String)

    case error(error: ErrorCode)
    case resetState
}
