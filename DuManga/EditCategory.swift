// Created 6/9/20

import SwiftUI
import NotificationBannerSwift

struct EditCategory: View {
    @Environment (\.presentationMode) var presentationMode

    @StateObject var editCategoryModel = EditCategoryModel()

    private let item: CategoryItem
    private let store = AppStore.shared

    init(item: CategoryItem) {
        self.item = item
    }

    var body: some View {
        NavigationStack {
            VStack {
                if item.archives.isEmpty {
                    VStack(alignment: .leading) {
                        Text("category.name")
                        TextField("name", text: $editCategoryModel.categoryName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                            .padding()
                    VStack(alignment: .leading) {
                        Text("category.search")
                        TextField("search", text: $editCategoryModel.searchKeyword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                            .padding()
                } else {
                    Text("Only support dynamic category edit for now.")
                }
            }
                    .navigationBarTitle("category.edit")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: {
                                presentationMode.wrappedValue.dismiss()
                            }, label: {
                                Text("cancel")
                            })
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(action: {
                                let updated: CategoryItem = CategoryItem(id: item.id,
                                        name: editCategoryModel.categoryName, archives: [],
                                        search: editCategoryModel.searchKeyword, pinned: item.pinned)
                                Task {
                                    if let error = await editCategoryModel.updateCategory(category: updated) {
                                        let banner = NotificationBanner(
                                                title: NSLocalizedString("error", comment: "error"),
                                                subtitle: error,
                                                style: .danger)
                                        banner.show()
                                    } else {
                                        store.dispatch(.category(action: .updateCategory(category: updated)))
                                        presentationMode.wrappedValue.dismiss()
                                    }
                                }
                            }, label: {
                                Text("done")
                            }).disabled(editCategoryModel.saving)
                        }
                    }
        }
                .onAppear(perform: {
                    editCategoryModel.load(name: item.name, keyword: item.search)
                })
    }
}
