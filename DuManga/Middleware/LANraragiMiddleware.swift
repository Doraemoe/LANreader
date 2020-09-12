//
// Created on 10/9/20.
//

import Foundation
import Combine

func lanraragiMiddleware(service: LANraragiService) -> Middleware<AppState, AppAction> {
    { state, action in
        switch action {
        case let .setting(action: .verifyAndSaveLanraragiConfig(url, apiKey)):
            return service.verifyClient(url: url, apiKey: apiKey)
                    .map { _ in
                        AppAction.setting(action: .saveLanraragiConfigToUserDefaults(url: url, apiKey: apiKey))
                    }
                    .replaceError(with: AppAction.setting(action: .error(errorCode: ErrorCode.lanraragiServerError)))
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
                    .replaceError(with: AppAction.category(action: .error(error: ErrorCode.categoryFetchError)))
                    .eraseToAnyPublisher()
        case let .category(action: .updateDynamicCategory(category)):
            return service.updateDynamicCategory(item: category)
                    .map { _ in
                        AppAction.category(action: .updateDynamicCategorySuccess(category: category))
                    }
                    .replaceError(with: AppAction.category(action: .error(error: ErrorCode.categoryUpdateError)))
                    .eraseToAnyPublisher()
        default:
            break
        }
        return Empty().eraseToAnyPublisher()
    }
}
