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
