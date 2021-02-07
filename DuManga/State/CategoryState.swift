//
// Created on 12/9/20.
//

import Foundation

struct CategoryState {
    @PublishedState var loading = false
    @PublishedState var categoryItems = [String: CategoryItem]()
    @PublishedState var updateDynamicCategorySuccess = false
    @PublishedState var errorCode: ErrorCode?

    init() {
        categoryItems["newOnly"] = CategoryItem(id: "newOnly",
                                                name: NSLocalizedString("category.new",
                                                                        comment: "Force use NSLocalizedString"),
                                                archives: [],
                                                search: "",
                                                pinned: "",
                                                isNew: true)
    }
}
