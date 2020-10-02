//
// Created on 12/9/20.
//

import Foundation

struct CategoryState {
    @PublishedState var loading = false
    @PublishedState var categoryItems = [String: CategoryItem]()
    @PublishedState var updateDynamicCategorySuccess = false
    @PublishedState var errorCode: ErrorCode?
}
