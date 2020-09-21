//
// Created on 13/9/20.
//

import Foundation

// swiftlint:disable cyclomatic_complexity
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
    case .extractArchive:
        state.loading = true
    case let .extractArchiveSuccess(id, pages):
        state.loading = false
        state.archivePages[id] = pages
    case let .replaceArchiveThumbnail(id, image):
        state.archiveItems[id]?.thumbnail = image
    case let .updateArchiveMetadataSuccess(metadata):
        state.archiveItems[metadata.id] = metadata
        state.updateArchiveMetadataSuccess = true
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
        state.updateArchiveMetadataSuccess = false
    default:
        break
    }
}
