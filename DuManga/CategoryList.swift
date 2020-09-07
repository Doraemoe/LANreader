//Created 27/8/20

import SwiftUI

struct CategoryList: View {
    @State var categoryItems = [CategoryItem]()
    @State var isLoading = false
    @State var showSheetView = false
    @State var selectedCategoryItem: CategoryItem? = nil
    
    @Binding var navBarTitle: String
    @Binding var editMode: EditMode
    
    private let config: [String: String]
    private let client: LANRaragiClient
    
    init(navBarTitle: Binding<String>, editMode: Binding<EditMode>) {
        self.config = UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String] ?? [String: String]()
        self.client = LANRaragiClient(url: config["url"]!, apiKey: config["apiKey"]!)
        self._navBarTitle = navBarTitle
        self._editMode = editMode
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                List(self.categoryItems) { (item: CategoryItem) in
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
                        NavigationLink(destination: ArchiveList(navBarTitle: self.$navBarTitle, searchKeyword: item.search, categoryArchives: item.archives, navBarTitleOverride: "category")) {
                            Text(item.name)
                                .font(.title)
                        }
                    }
                }
                .sheet(isPresented: self.$showSheetView) {
                    EditCategory(item: self.selectedCategoryItem!, showSheetView: self.$showSheetView)
                        .onDisappear(perform: {
                            self.categoryItems = [CategoryItem]()
                            self.loadData()
                        })
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
            items?.forEach { item in
                self.categoryItems.append(CategoryItem(id: item.id, name: item.name, archives: item.archives, search: item.search, pinned: item.pinned))
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
