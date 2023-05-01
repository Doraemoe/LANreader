//
// Created on 12/9/20.
//

import Foundation
import Combine

func categoryReducer(state: inout CategoryState, action: CategoryAction) {
    switch action {
    case .startFetchCategory:
        state.loading = true
    case .finishFetchCategory:
        state.loading = false
    case let .storeCategory(categoryItems):
        state.categoryItems = categoryItems
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case let .updateCategory(category):
        state.categoryItems[category.id] = category
        state.updateDynamicCategorySuccess = true
    case .resetState:
        state.errorCode = nil
        state.updateDynamicCategorySuccess = false
    }
}
