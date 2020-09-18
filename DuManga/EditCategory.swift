//Created 6/9/20

import SwiftUI
import NotificationBannerSwift

struct EditCategory: View {

    @EnvironmentObject var store: AppStore

    @State var categoryName = ""
    @State var searchKeyword = ""

    @Binding var showSheetView: Bool

    let item: CategoryItem

    init(item: CategoryItem, showSheetView: Binding<Bool>) {
        self.item = item
        self._showSheetView = showSheetView
    }

    var body: some View {
        if store.state.category.errorCode != nil {
            let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                    subtitle: NSLocalizedString("error.category.update", comment: "update category error"),
                    style: .danger)
            banner.show()
            self.store.dispatch(.category(action: .resetState))
        } else if store.state.category.updateDynamicCategorySuccess {
            self.store.dispatch(.category(action: .resetState))
            self.showSheetView = false
        }
        return NavigationView {
            VStack {
                if item.archives.isEmpty {
                    VStack(alignment: .leading) {
                        Text("category.name")
                        TextField("name", text: self.$categoryName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                            .padding()
                            .onAppear(perform: {
                                self.categoryName = self.item.name
                                self.searchKeyword = self.item.search
                            })
                    VStack(alignment: .leading) {
                        Text("category.search")
                        TextField("search", text: self.$searchKeyword)
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
                                name: self.categoryName, archives: [],
                                search: self.searchKeyword, pinned: self.item.pinned)
                        self.store.dispatch(.category(action: .updateDynamicCategory(category: updated)))
                    }, label: {
                        Text("done")
                    }))
        }
                .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct EditCategory_Previews: PreviewProvider {
    static var previews: some View {
        EditCategory(item: CategoryItem(id: "id", name: "name", archives: [], search: "search", pinned: "0"),
                showSheetView: Binding.constant(true))
    }
}
