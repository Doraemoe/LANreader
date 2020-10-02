//Created 27/8/20

import SwiftUI
import NotificationBannerSwift

struct CategoryList: View {
    @EnvironmentObject var store: AppStore
    @StateObject var categoryListModel = CategoryListModel()

    @Binding var navBarTitle: String
    @Binding var editMode: EditMode

    init(navBarTitle: Binding<String>, editMode: Binding<EditMode>) {
        self._navBarTitle = navBarTitle
        self._editMode = editMode
    }

    var body: some View {
        let categories = Array(categoryListModel.categoryItems.values).sorted(by: { $0.name < $1.name })
        return GeometryReader { geometry in
            ZStack {
                List(categories) { (item: CategoryItem) in
                    if self.editMode == .active {
                        ZStack(alignment: .leading) {
                            Text(item.name)
                                    .font(.title)
                            Rectangle()
                                    .opacity(0.0001)
                                    .contentShape(Rectangle())
                                    .onTapGesture(perform: {
                                        categoryListModel.selectedCategoryItem = item
                                        categoryListModel.showSheetView = true
                                    })
                        }
                    } else {
                        NavigationLink(destination: ArchiveList(navBarTitle: self.$navBarTitle,
                                searchKeyword: item.search,
                                categoryArchives: item.archives,
                                navBarTitleOverride: "category")) {
                            Text(item.name)
                                    .font(.title)
                        }
                    }
                }
                        .sheet(isPresented: $categoryListModel.showSheetView) {
                            EditCategory(item: categoryListModel.selectedCategoryItem!,
                                    showSheetView: $categoryListModel.showSheetView)
                                    .environmentObject(self.store)
                        }
                        .onAppear(perform: { self.navBarTitle = "category" })
                        .onAppear(perform: self.loadData)

                VStack {
                    Text("loading")
                    ProgressView()
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary)
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(self.categoryListModel.loading ? 1 : 0)
            }
                    .onAppear(perform: {
                        categoryListModel.load(state: self.store.state)
                    })
                    .onDisappear(perform: {
                        categoryListModel.unload()
                    })
                    .onChange(of: self.categoryListModel.errorCode, perform: { code in
                        if code != nil {
                            let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                    subtitle: NSLocalizedString("error.category", comment: "category error"),
                                    style: .danger)
                            banner.show()
                            store.dispatch(.category(action: .resetState))
                        }
                    })
        }
    }

    func loadData() {
        if self.categoryListModel.categoryItems.count > 0 {
            return
        }
        self.store.dispatch(.category(action: .fetchCategory))
    }
}

struct CategoryList_Previews: PreviewProvider {
    static var previews: some View {
        let config = ["url": "http://localhost", "apiKey": "apiKey"]
        UserDefaults.standard.set(config, forKey: "LANraragi")
        return CategoryList(navBarTitle: Binding.constant("categories"), editMode: Binding.constant(.active))
    }
}
