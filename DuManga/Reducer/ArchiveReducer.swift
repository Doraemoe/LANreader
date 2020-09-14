//
// Created on 13/9/20.
//

import Foundation

func archiveReducer(state: inout ArchiveState, action: ArchiveAction) {
    switch action {
    case .fetchArchive:
        state.loading = true
    case let .fetchArchiveSuccess(archiveItems):
        state.loading = false
        state.archiveItems = archiveItems
    case .fetchArchiveDynamicCategory:
        state.loading = true
        state.dynamicCategoryKeys = [String]()
    case let .fetchArchiveDynamicCategorySuccess(keys):
        state.loading = false
        state.dynamicCategoryKeys = keys
    case let .replaceArchiveThumbnail(id, image):
        state.archiveItems[id]?.thumbnail = image
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
    default:
        break
    }
}
