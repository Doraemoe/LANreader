//
// Created on 12/9/20.
//

import Foundation
import Combine

func categoryReducer(state: inout CategoryState, action: CategoryAction) {
    switch action {
    case .fetchCategory:
        state.loading = true
    case let .fetchCategorySuccess(categoryItems):
        state.loading = false
        state.categoryItems = categoryItems
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case let .updateDynamicCategorySuccess(category):
        state.categoryItems[category.id] = category
        state.updateDynamicCategorySuccess = true
    case .resetState:
        state.errorCode = nil
        state.updateDynamicCategorySuccess = false
    default:
        break;
    }
}
