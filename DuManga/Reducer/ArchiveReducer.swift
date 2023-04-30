//
// Created on 13/9/20.
//

import Foundation

// swiftlint:disable all
func archiveReducer(state: inout ArchiveState, action: ArchiveAction) {
    switch action {
    case let .storeArchive(archiveItems):
        state.archiveItems = archiveItems
    case .startFetchArchive:
        state.loading = true
    case .finishFetchArchive:
        state.loading = false
    case .fetchArchiveDynamicCategory:
        state.loading = true
    case .fetchArchiveDynamicCategorySuccess:
        state.loading = false
    case .updateArchiveMetadata:
        state.loading = true
    case let .updateArchiveMetadataSuccess(metadata):
        state.archiveItems[metadata.id] = metadata
        state.updateArchiveMetadataSuccess = true
        state.loading = false
    case let .updateReadProgressLocal(id, progress):
        let archive = state.archiveItems[id]!
        state.archiveItems[id] = ArchiveItem(id: archive.id,
                name: archive.name,
                tags: archive.tags,
                isNew: archive.isNew,
                progress: progress,
                pagecount: archive.pagecount,
                dateAdded: archive.dateAdded)
    case .deleteArchive:
        state.loading = true
    case let .deleteArchiveSuccess(id):
        state.archiveItems.removeValue(forKey: id)
        state.deleteArchiveSuccess = true
        state.loading = false
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
        state.updateArchiveMetadataSuccess = false
        state.deleteArchiveSuccess = false
    default:
        break
    }
}
// swiftlint:enable all
