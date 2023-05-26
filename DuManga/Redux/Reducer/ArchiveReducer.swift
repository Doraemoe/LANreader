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
    case let .updateArchive(archive):
        state.archiveItems[archive.id] = archive
    case let .updateReadProgress(id, progress):
        let archive = state.archiveItems[id]!
        state.archiveItems[id] = ArchiveItem(id: archive.id,
                name: archive.name,
                tags: archive.tags,
                isNew: archive.isNew,
                progress: progress,
                pagecount: archive.pagecount,
                dateAdded: archive.dateAdded)
    case let .removeDeletedArchive(id):
        state.archiveItems.removeValue(forKey: id)
    case let .setRandomOrderSeed(seed):
        state.randomOrderSeed = seed
    case .clearArchive:
        state.archiveItems = .init()
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
    }
}
// swiftlint:enable all
