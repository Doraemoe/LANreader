//
// Created on 10/9/20.
//

import Foundation
import Combine
import SwiftUI

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

        case .archive(action: .fetchArchive):
            return service.retrieveArchiveIndex()
                    .map { (response: [ArchiveIndexResponse]) in
                        var archiveItems = [String: ArchiveItem]()
                        response.forEach { item in
                            archiveItems[item.arcid] = ArchiveItem(id: item.arcid,
                                    name: item.title,
                                    tags: item.tags ?? "",
                                    isNew: item.isnew == "true",
                                    progress: item.progress,
                                    pagecount: item.pagecount,
                                    dateAdded: extractDateAdded(tags: item.tags ?? ""))
                        }
                        return AppAction.archive(action: .fetchArchiveSuccess(archive: archiveItems))
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveFetchError)))
                    .eraseToAnyPublisher()
        case let .archive(action: .updateArchiveMetadata(metadata)):
            return service.updateArchiveMetaData(archiveMetadata: metadata)
                    .map { _ in
                        AppAction.archive(action: .updateArchiveMetadataSuccess(metadata: metadata))
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveUpdateMetadataError)))
                    .eraseToAnyPublisher()
        case let .archive(action: .deleteArchive(id)):
            return service.deleteArchive(id: id)
                    .map { (response: ArchiveDeleteResponse) in
                        let success = response.success
                        if success == 1 {
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
                        AppAction.archive(action: .updateReadProgressLocal(id: id, progress: progress))
                    }
                    .replaceError(with: AppAction.noop)
                    .eraseToAnyPublisher()
        case .category(action: .fetchCategory):
            return service.retrieveCategories()
                    .map { (response: [ArchiveCategoriesResponse]) in
                        var categoryItems = [String: CategoryItem]()
                        categoryItems["newOnly"] = CategoryItem(id: "newOnly",
                                name: NSLocalizedString("category.new",
                                        comment: "new"),
                                archives: [],
                                search: "",
                                pinned: "",
                                isNew: true)
                        response.forEach { item in
                            categoryItems[item.id] = CategoryItem(id: item.id, name: item.name,
                                    archives: item.archives, search: item.search, pinned: item.pinned, isNew: false)
                        }
                        return AppAction.category(action: .fetchCategorySuccess(category: categoryItems))
                    }
                    .replaceError(with: AppAction.category(action: .error(error: .categoryFetchError)))
                    .eraseToAnyPublisher()
        case let .category(action: .updateDynamicCategory(category)):
            return service.updateDynamicCategory(item: category)
                    .map { _ in
                        AppAction.category(action: .updateDynamicCategorySuccess(category: category))
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
