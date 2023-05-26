//
// Created on 12/9/20.
//

import Foundation
import Logging

enum CategoryAction {
    case startFetchCategory
    case finishFetchCategory
    case storeCategory(category: [String: CategoryItem])
    case updateCategory(category: CategoryItem)
    case clearCategory
    case error(error: ErrorCode)
    case resetState
}

// MARK: thunk actions

private let logger = Logger(label: "CategoryAction")
private let database = AppDatabase.shared
private let lanraragiService = LANraragiService.shared

func fetchCategory(fromServer: Bool) async -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        dispatch(.category(action: .startFetchCategory))
        if !fromServer {
            do {
                let categories = try database.readAllCategories()
                if categories.count > 0 {
                    var categoryItems = [String: CategoryItem]()
                    categories.forEach { item in
                        categoryItems[item.id] = item.toCategoryItem()
                    }
                    dispatch(.category(action: .storeCategory(category: categoryItems)))
                    dispatch(.category(action: .finishFetchCategory))
                    return
                }
            } catch {
                logger.warning("failed to read catagory from db. \(error)")
            }
        }
        do {
            let categories = try await lanraragiService.retrieveCategories().value
            _ = try? database.deleteAllCategory()
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
            dispatch(.category(action: .storeCategory(category: categoryItems)))
        } catch {
            logger.error("failed to retrieve category. \(error)")
            dispatch(.category(action: .error(error: .categoryFetchError)))
        }
        dispatch(.category(action: .finishFetchCategory))
    }
}
