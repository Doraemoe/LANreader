//
// Created on 13/9/20.
//

import Foundation
import SwiftUI
import Logging

enum ArchiveAction {
    case startFetchArchive
    case finishFetchArchive
    case storeArchive(archive: [String: ArchiveItem])

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

// thunk actions

private let logger = Logger(label: "ArchiveAction")
private let database = AppDatabase.shared
private let lanraragiService = LANraragiService.shared

let fetchArchiveAsync: ThunkAction<AppAction, AppState> = {dispatch, _ in
    dispatch(.archive(action: .startFetchArchive))
    do {
        let archives = try await lanraragiService.retrieveArchiveIndex().value
        var archiveItems = [String: ArchiveItem]()
        archives.forEach { item in
            archiveItems[item.arcid] = item.toArchiveItem()
            do {
                var archive = item.toArchive()
                try database.saveArchive(&archive)
            } catch {
                logger.error("failed to save archive. id=\(item.arcid) \(error)")
            }
        }
        dispatch(.archive(action: .storeArchive(archive: archiveItems)))
    } catch {
        logger.error("failed to fetch archive. \(error)")
        dispatch(.archive(action: .error(error: .archiveFetchError)))
    }
    dispatch(.archive(action: .finishFetchArchive))
}
