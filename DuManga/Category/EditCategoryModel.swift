//
// Created on 2/10/20.
//

import Foundation
import Logging

@Observable
class EditCategoryModel {
    private static let logger = Logger(label: "CategoryAction")
    var categoryName = ""
    var searchKeyword = ""
    var saving = false

    private let database = AppDatabase.shared
    private let lanraragiService = LANraragiService.shared

    func load(name: String, keyword: String) {
        categoryName = name
        searchKeyword = keyword
    }

    @MainActor
    func updateCategory(category: CategoryItem) async -> String? {
        saving = true
        do {
            _ = try await lanraragiService.updateDynamicCategory(item: category).value
            do {
                var categoryDto = category.toCategory()
                try database.saveCategory(&categoryDto)
            } catch {
                EditCategoryModel.logger.warning("failed to save category. id=\(category.id) \(error)")
            }
            saving = false
            return nil
        } catch {
            EditCategoryModel.logger.error("failed to update category. id=\(category.id) \(error)")
            saving = false
            return error.localizedDescription
        }
    }
}
