//
// Created on 10/9/20.
//

import Foundation
import Combine
import SwiftUI

func lanraragiMiddleware(service: LANraragiService) -> Middleware<AppState, AppAction> {
    { state, action in
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
                            archiveItems[item.arcid] = ArchiveItem(id: item.arcid, name: item.title,
                                    tags: item.tags, thumbnail: Image("placeholder"))
                        }
                        return AppAction.archive(action: .fetchArchiveSuccess(archive: archiveItems))
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveFetchError)))
                    .eraseToAnyPublisher()
        case let .archive(action: .fetchArchiveThumbnail(id)):
            return service.retrieveArchiveThumbnail(id: id)
                    .map { (img: UIImage) in
                        AppAction.archive(action: .replaceArchiveThumbnail(id: id, image: Image(uiImage: img)))
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveThumbnailError)))
                    .eraseToAnyPublisher()
        case let .archive(action: .fetchArchiveDynamicCategory(keyword)):
            return service.searchArchiveIndex(filter: keyword)
                    .map { (response: ArchiveSearchResponse) in
                        var keys = [String]()
                        response.data.forEach { item in
                            keys.append(item.arcid)
                        }
                        return AppAction.archive(action: .fetchArchiveDynamicCategorySuccess(keys: keys))
                    }
                    .replaceError(with: AppAction.archive(action: .error(error: .archiveFetchError)))
                    .eraseToAnyPublisher()
        case .category(action: .fetchCategory):
            return service.retrieveCategories()
                    .map { (response: [ArchiveCategoriesResponse]) in
                        var categoryItems = [String: CategoryItem]()
                        response.forEach { item in
                            categoryItems[item.id] = CategoryItem(id: item.id, name: item.name,
                                    archives: item.archives, search: item.search, pinned: item.pinned)
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
