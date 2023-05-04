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

    case startUpdateArchive
    case finishUpdateArchive
    case updateArchive(archive: ArchiveItem)

    case updateReadProgress(id: String, progress: Int)

    case startDeleteArchive
    case finishDeleteArchive
    case removeDeletedArchive(id: String)

    case setRandomOrderSeed(seed: UInt64)

    case error(error: ErrorCode)
    case resetState
}

// MARK: thunk actions

private let logger = Logger(label: "ArchiveAction")
private let database = AppDatabase.shared
private let lanraragiService = LANraragiService.shared

func fetchArchives(_ fromServer: Bool) -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        dispatch(.archive(action: .startFetchArchive))
        if !fromServer {
            do {
                let archives = try database.readAllArchive()
                if archives.count > 0 {
                    var archiveItems = [String: ArchiveItem]()
                    archives.forEach { item in
                        archiveItems[item.id] = item.toArchiveItem()
                    }
                    dispatch(.archive(action: .storeArchive(archive: archiveItems)))
                    dispatch(.archive(action: .finishFetchArchive))
                    return
                }
            } catch {
                logger.warning("failed to read archive from db. \(error)")
            }
        }

        do {
            let archives = try await lanraragiService.retrieveArchiveIndex().value
            _ = try? database.deleteAllArchive()
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
}

func updateArchive(archive: ArchiveItem) -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        dispatch(.archive(action: .startUpdateArchive))
        do {
            _ = try await lanraragiService.updateArchive(archive: archive).value
            do {
                var archiveDto = archive.toArchive()
                try database.saveArchive(&archiveDto)
            } catch {
                logger.error("failed to save archive. id=\(archive.id) \(error)")
            }
            dispatch(.archive(action: .updateArchive(archive: archive)))
        } catch {
            logger.error("failed to save archive. id=\(archive.id) \(error)")
        }
        dispatch(.archive(action: .finishUpdateArchive))
    }
}

func deleteArchive(id: String) -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        dispatch(.archive(action: .startDeleteArchive))
        do {
            let response = try await lanraragiService.deleteArchive(id: id).value
            if response.success == 1 {
                do {
                    let success = try database.deleteArchive(id)
                    if !success {
                        logger.error("failed to delete archive from db. id=\(id)")
                    }
                } catch {
                    logger.error("failed to delete archive from db. id=\(id) \(error)")
                }
                dispatch(.archive(action: .removeDeletedArchive(id: id)))
            } else {
                dispatch(.archive(action: .error(error: .archiveDeleteError)))
            }
        } catch {
            logger.error("failed to delete archive. id=\(id) \(error)")
            dispatch(.archive(action: .error(error: .archiveDeleteError)))
        }
        dispatch(.archive(action: .finishDeleteArchive))
    }
}

func updateReadProgress(id: String, progress: Int) -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        do {
            _ = try await lanraragiService.updateArchiveReadProgress(id: id, progress: progress).value
            do {
                let updated = try database.updateArchiveProgress(id, progress: progress)
                if updated == 0 {
                    logger.warning("No archive progress updated. id=\(id)")
                }
            } catch {
                logger.error("failed to update archive progress. id=\(id) \(error)")
            }
            dispatch(.archive(action: .updateReadProgress(id: id, progress: progress)))
        } catch {
            logger.error("failed to update archive progress. id=\(id) \(error)")
        }
    }
}
