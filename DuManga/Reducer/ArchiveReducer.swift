//
// Created on 13/9/20.
//

import Foundation

// swiftlint:disable all
func archiveReducer(state: inout ArchiveState, action: ArchiveAction) {
    switch action {
    case .startFetchArchive:
        state.loading = true
    case .finishFetchArchive:
        state.loading = false
    case let .storeArchive(archiveItems):
        state.archiveItems = archiveItems
    case .fetchArchiveDynamicCategory:
        state.loading = true
    case .fetchArchiveDynamicCategorySuccess:
        state.loading = false
    case .startUpdateArchive:
        state.loading = true
    case .finishUpdateArchive:
        state.loading = false
    case let .updateArchive(archive):
        state.archiveItems[archive.id] = archive
        state.updateArchiveSuccess = true
        state.loading = false
    case let .updateReadProgress(id, progress):
        let archive = state.archiveItems[id]!
        state.archiveItems[id] = ArchiveItem(id: archive.id,
                name: archive.name,
                tags: archive.tags,
                isNew: archive.isNew,
                progress: progress,
                pagecount: archive.pagecount,
                dateAdded: archive.dateAdded)
    case .startDeleteArchive:
        state.loading = true
    case .finishDeleteArchive:
        state.loading = false
    case let .removeDeletedArchive(id):
        state.archiveItems.removeValue(forKey: id)
        state.deleteArchiveSuccess = true
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
        state.updateArchiveSuccess = false
        state.deleteArchiveSuccess = false
    }
}
// swiftlint:enable all
