//Created 6/9/20

import SwiftUI
import NotificationBannerSwift

struct EditCategory: View {

    @State var categoryName = ""
    @State var searchKeyword = ""

    @Binding var showSheetView: Bool
    @Binding var categoryItems: [String: CategoryItem]

    let item: CategoryItem
    private let config: [String: String]
    private let client: LANRaragiClient

    init(item: CategoryItem, showSheetView: Binding<Bool>, categoryItems: Binding<[String: CategoryItem]>) {
        self.item = item
        self.config = UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String] ?? [String: String]()
        self.client = LANRaragiClient(url: config["url"]!, apiKey: config["apiKey"]!)
        self._showSheetView = showSheetView
        self._categoryItems = categoryItems
    }

    var body: some View {
        NavigationView {
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
                    }) {
                        Text("cancel")
                    }, trailing: Button(action: {
                        let updated: CategoryItem = CategoryItem(id: self.item.id,
                                name: self.categoryName, archives: [], search: self.searchKeyword, pinned: self.item.pinned)
                        self.client.updateSearchCategory(item: updated) { success in
                            if success {
                                self.categoryItems[updated.id] = updated
                                self.showSheetView = false
                            } else {
                                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                        subtitle: NSLocalizedString("error.category.update", comment: "update category error"),
                                        style: .danger)
                                banner.show()
                            }
                        }

                    }) {
                        Text("done")
                    })
        }
                .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct EditCategory_Previews: PreviewProvider {
    static var previews: some View {
        EditCategory(item: CategoryItem(id: "id", name: "name", archives: [], search: "search", pinned: "0"),
                showSheetView: Binding.constant(true), categoryItems: Binding.constant([String: CategoryItem]()))
    }
}
