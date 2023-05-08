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
    case updateArchive(archive: ArchiveItem)
    case updateReadProgress(id: String, progress: Int)
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
