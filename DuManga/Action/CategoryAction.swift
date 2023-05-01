//
// Created on 12/9/20.
//

import Foundation
import Logging

enum CategoryAction {
    case startFetchCategory
    case finishFetchCategory
    case storeCategory(category: [String: CategoryItem])

    case error(error: ErrorCode)
    case updateCategory(category: CategoryItem)
    case resetState
}

// MARK: thunk actions

private let logger = Logger(label: "CategoryAction")
private let database = AppDatabase.shared
private let lanraragiService = LANraragiService.shared

func fetchCategory(fromServer: Bool) async -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        if !fromServer {
            do {
                let categories = try database.readAllCategories()
                if categories.count > 0 {
                    var categoryItems = [String: CategoryItem]()
                    categories.forEach { item in
                        categoryItems[item.id] = item.toCategoryItem()
                    }
                    dispatch(.category(action: .storeCategory(category: categoryItems)))
                    return
                }
            } catch {
                logger.warning("failed to read catagory from db. \(error)")
            }
        }
        dispatch(.category(action: .startFetchCategory))
        do {
            let categories = try await lanraragiService.retrieveCategories().value
            var categoryItems = [String: CategoryItem]()
            categories.forEach { item in
                categoryItems[item.id] = item.toCategoryItem()
                do {
                    var category = item.toCategory()
                    try database.saveCategory(&category)
                } catch {
                    logger.error("failed to save category. id=\(item.id) \(error)")
                }
            }
        } catch {
            logger.error("failed to retrieve category. \(error)")
            dispatch(.category(action: .error(error: .categoryFetchError)))
        }
        dispatch(.category(action: .finishFetchCategory))
    }
}

func updateDynamicCategory(category: CategoryItem) async -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        do {
            _ = try await lanraragiService.updateDynamicCategory(item: category).value
            do {
                var categoryDto = category.toCategory()
                try database.saveCategory(&categoryDto)
            } catch {
                logger.warning("failed to save category. id=\(category.id) \(error)")
            }
            dispatch(.category(action: .updateCategory(category: category)))
        } catch {
            logger.error("failed to update category. id=\(category.id) \(error)")
            dispatch(.category(action: .error(error: .categoryUpdateError)))
        }
    }
}
