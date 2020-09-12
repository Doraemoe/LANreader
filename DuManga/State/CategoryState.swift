//
// Created on 12/9/20.
//

import Foundation

struct CategoryState {
    var loading: Bool
    var categoryItems: [String: CategoryItem]
    var errorCode: ErrorCode?
    var updateDynamicCategorySuccess: Bool

    init() {
        // list
        self.loading = false
        self.categoryItems = [String: CategoryItem]()
        self.errorCode = nil

        // update
        self.updateDynamicCategorySuccess = false
    }
}
