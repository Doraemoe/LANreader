//
// Created on 12/9/20.
//

import Foundation

enum CategoryAction {
    case fetchCategory
    case fetchCategorySuccess(category: [String: CategoryItem])
    case error(error: ErrorCode)
    case updateDynamicCategory(category: CategoryItem)
    case updateDynamicCategorySuccess(category: CategoryItem)
    case resetState
}
