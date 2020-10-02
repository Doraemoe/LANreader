//Created 6/9/20

import SwiftUI
import NotificationBannerSwift

struct EditCategory: View {

    @EnvironmentObject var store: AppStore
    @StateObject var editCategoryModel = EditCategoryModel()

    @Binding var showSheetView: Bool

    let item: CategoryItem

    init(item: CategoryItem, showSheetView: Binding<Bool>) {
        self.item = item
        self._showSheetView = showSheetView
    }

    var body: some View {
        NavigationView {
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
                    .navigationBarTitle("category.edit", displayMode: .inline)
                    .navigationBarItems(leading: Button(action: {
                        self.showSheetView = false
                    }, label: {
                        Text("cancel")
                    }), trailing: Button(action: {
                        let updated: CategoryItem = CategoryItem(id: self.item.id,
                                name: editCategoryModel.categoryName, archives: [],
                                search: editCategoryModel.searchKeyword, pinned: self.item.pinned)
                        self.store.dispatch(.category(action: .updateDynamicCategory(category: updated)))
                    }, label: {
                        Text("done")
                    }))
        }
                .onAppear(perform: {
                    editCategoryModel.load(state: store.state, name: self.item.name, keyword: self.item.search)
                })
                .onDisappear(perform: {
                    editCategoryModel.unload()
                })
                .onChange(of: editCategoryModel.errorCode, perform: { errorCode in
                    if errorCode != nil {
                        let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                subtitle: NSLocalizedString("error.category.update", comment: "update category error"),
                                style: .danger)
                        banner.show()
                        self.store.dispatch(.category(action: .resetState))
                    }
                })
                .onChange(of: editCategoryModel.updateDynamicCategorySuccess, perform: { success in
                    if success {
                        self.store.dispatch(.category(action: .resetState))
                        self.showSheetView = false
                    }
                })
                .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct EditCategory_Previews: PreviewProvider {
    static var previews: some View {
        EditCategory(item: CategoryItem(id: "id", name: "name", archives: [], search: "search", pinned: "0"),
                showSheetView: Binding.constant(true))
    }
}
