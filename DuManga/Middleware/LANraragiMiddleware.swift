//
// Created on 10/9/20.
//

import Foundation
import Combine
import SwiftUI
import Logging

private let logger = Logger(label: "LANraragiMiddleware")
private let database = AppDatabase.shared
// swiftlint:disable function_body_length
func lanraragiMiddleware(service: LANraragiService) -> Middleware<AppState, AppAction> {
    { _, action in
        switch action {
        case let .setting(action: .verifyAndSaveLanraragiConfig(url, apiKey)):
            return service.verifyClient(url: url, apiKey: apiKey)
                    .map { _ in
                        AppAction.setting(action: .saveLanraragiConfigToUserDefaults(url: url, apiKey: apiKey))
                    }
                    .replaceError(with: AppAction.setting(action: .error(errorCode: .lanraragiServerError)))
                    .eraseToAnyPublisher()

        case let .archive(action: .fetchArchive(fromServer)):
            if !fromServer {
                do {
                    let archives = try database.readAllArchive()
                    if archives.count > 0 {
                        var archiveItems = [String: ArchiveItem]()
                        archives.forEach { item in
                            archiveItems[item.id] = item.toArchiveItem()
                        }
                        return Just(AppAction.archive(action: .fetchArchiveSuccess(archive: archiveItems)))
                                .eraseToAnyPublisher()
                    }
                } catch {
                    logger.warning("failed to read archive from db. \(error)")
                }
            }
            return service.retrieveArchiveIndex()
                    .map { (response: [ArchiveIndexResponse]) in
                        var archiveItems = [String: ArchiveItem]()
                        response.forEach { item in
                            archiveItems[item.arcid] = item.toArchiveItem()
                            do {
                                var archive = item.toArchive()
                                try database.saveArchive(&archive)
                            } catch {
                                logger.error("failed to save archive. id=\(item.arcid) \(error)")
                            }
                        }
                        return AppAction.archive(action: .fetchArchiveSuccess(archive: archiveItems))
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveFetchError)))
                    .eraseToAnyPublisher()
        case let .archive(action: .updateArchiveMetadata(metadata)):
            return service.updateArchiveMetaData(archiveMetadata: metadata)
                    .map { _ in
                        do {
                            var archive = metadata.toArchive()
                            try database.saveArchive(&archive)
                        } catch {
                            logger.error("failed to save archive. id=\(metadata.id) \(error)")
                        }
                        return AppAction.archive(action: .updateArchiveMetadataSuccess(metadata: metadata))
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveUpdateMetadataError)))
                    .eraseToAnyPublisher()
        case let .archive(action: .deleteArchive(id)):
            return service.deleteArchive(id: id)
                    .map { (response: ArchiveDeleteResponse) in
                        let success = response.success
                        if success == 1 {
                            do {
                                let success = try database.deleteArchive(id)
                                if !success {
                                    logger.error("failed to delete archive. id=\(id)")
                                }
                            } catch {
                                logger.error("failed to delete archive. id=\(id) \(error)")
                            }
                            return AppAction.archive(action: .deleteArchiveSuccess(id: id))
                        } else {
                            return AppAction.archive(action: .error(error: .archiveDeleteError))
                        }
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveDeleteError)))
                    .eraseToAnyPublisher()
        case let .page(action: .extractArchive(id)):
            return service.extractArchive(id: id)
                    .map { (response: ArchiveExtractResponse) in
                        var allPages = [String]()
                        response.pages.forEach { page in
                            let normalizedPage = String(page.dropFirst(2))
                            allPages.append(normalizedPage)
                        }
                        return AppAction.page(action: .extractArchiveSuccess(id: id, pages: allPages))
                    }
                    .replaceError(with: AppAction.page(action: .error(error: .archiveExtractError)))
                    .eraseToAnyPublisher()
        case let .archive(action: .updateReadProgressServer(id, progress)):
            return service.updateArchiveReadProgress(id: id, progress: progress)
                    .map { _ in
                        do {
                            let updated = try database.updateArchiveProgress(id, progress: progress)
                            if updated == 0 {
                                logger.warning("No archive progress updated. id=\(id)")
                            }
                        } catch {
                            logger.error("failed to update archive progress. id=\(id) \(error)")
                        }
                        return AppAction.archive(action: .updateReadProgressLocal(id: id, progress: progress))
                    }
                    .replaceError(with: AppAction.noop)
                    .eraseToAnyPublisher()
        case let .category(action: .fetchCategory(fromServer)):
            if !fromServer {
                do {
                    let categories = try database.readAllCategories()
                    if categories.count > 0 {
                        var categoryItems = [String: CategoryItem]()
                        categories.forEach { item in
                            categoryItems[item.id] = item.toCategoryItem()
                        }
                        return Just(AppAction.category(action: .fetchCategorySuccess(category: categoryItems)))
                                .eraseToAnyPublisher()
                    }
                } catch {
                    logger.warning("failed to read catagory from db. \(error)")
                }
            }
            return service.retrieveCategories()
                    .map { (response: [ArchiveCategoriesResponse]) in
                        var categoryItems = [String: CategoryItem]()
                        response.forEach { item in
                            categoryItems[item.id] = item.toCategoryItem()
                            do {
                                var category = item.toCategory()
                                try database.saveCategory(&category)
                            } catch {
                                logger.error("failed to save category. id=\(item.id) \(error)")
                            }
                        }
                        return AppAction.category(action: .fetchCategorySuccess(category: categoryItems))
                    }
                    .replaceError(with: AppAction.category(action: .error(error: .categoryFetchError)))
                    .eraseToAnyPublisher()
        case let .category(action: .updateDynamicCategory(category)):
            return service.updateDynamicCategory(item: category)
                    .map { _ in
                        do {
                            var category = category.toCategory()
                            try database.saveCategory(&category)
                        } catch {
                            logger.error("failed to save category. id=\(category.id) \(error)")
                        }
                        return AppAction.category(action: .updateDynamicCategorySuccess(category: category))
                    }
                    .replaceError(with: AppAction.category(action: .error(error: .categoryUpdateError)))
                    .eraseToAnyPublisher()
        default:
            break
        }
        return Empty().eraseToAnyPublisher()
    }
}

func extractDateAdded(tags: String) -> Int? {
    let dateString = tags.split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.starts(with: "date_added") })?
            .split(separator: ":")
            .last
    if let date = dateString {
        return Int(date)
    } else {
        return nil
    }
}

// swiftlint:enable function_body_length
