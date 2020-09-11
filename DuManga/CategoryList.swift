//Created 27/8/20

import SwiftUI
import NotificationBannerSwift

struct CategoryList: View {
    @State var categoryItems = [String: CategoryItem]()
    @State var isLoading = false
    @State var showSheetView = false
    @State var selectedCategoryItem: CategoryItem? = nil

    @Binding var navBarTitle: String
    @Binding var editMode: EditMode

    private let client: LANRaragiClient

    init(navBarTitle: Binding<String>, editMode: Binding<EditMode>) {
        self.client = LANRaragiClient(url: UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl)!,
                apiKey: UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey)!)
        self._navBarTitle = navBarTitle
        self._editMode = editMode
    }

    var body: some View {
        let categories = Array(self.categoryItems.values).sorted(by: { $0.name < $1.name })
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
                                        self.selectedCategoryItem = item
                                        self.showSheetView = true
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
                        .sheet(isPresented: self.$showSheetView) {
                            EditCategory(item: self.selectedCategoryItem!,
                                    showSheetView: self.$showSheetView,
                                    categoryItems: self.$categoryItems)
                        }
                        .onAppear(perform: { self.navBarTitle = "category" })
                        .onAppear(perform: self.loadData)

                VStack {
                    Text("loading")
                    ActivityIndicator(isAnimating: self.$isLoading, style: .large)
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary.colorInvert())
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(self.isLoading ? 1 : 0)
            }
        }
    }

    func loadData() {
        if self.categoryItems.count > 0 {
            return
        }
        self.isLoading = true
        client.getCategories { (items: [ArchiveCategoriesResponse]?) in
            if items == nil {
                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                        subtitle: NSLocalizedString("error.category", comment: "category error"), style: .danger)
                banner.show()
            }
            items?.forEach { item in
                if self.categoryItems[item.id] == nil {
                    self.categoryItems[item.id] = CategoryItem(id: item.id, name: item.name,
                            archives: item.archives, search: item.search, pinned: item.pinned)
                }
            }
            self.isLoading = false
        }
    }
}

struct CategoryList_Previews: PreviewProvider {
    static var previews: some View {
        let config = ["url": "http://localhost", "apiKey": "apiKey"]
        UserDefaults.standard.set(config, forKey: "LANraragi")
        return CategoryList(navBarTitle: Binding.constant("categories"), editMode: Binding.constant(.active))
    }
}
