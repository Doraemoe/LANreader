//Created 27/8/20

import SwiftUI
import NotificationBannerSwift

struct CategoryList: View {
    @EnvironmentObject var store: AppStore

    @State var showSheetView = false
    @State var selectedCategoryItem: CategoryItem? = nil

    @Binding var navBarTitle: String
    @Binding var editMode: EditMode


    init(navBarTitle: Binding<String>, editMode: Binding<EditMode>) {
        self._navBarTitle = navBarTitle
        self._editMode = editMode
    }

    var body: some View {
        let categories = Array(self.store.state.category.categoryItems.values).sorted(by: { $0.name < $1.name })
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
                                    showSheetView: self.$showSheetView)
                                    .environmentObject(self.store)
                        }
                        .onAppear(perform: { self.navBarTitle = "category" })
                        .onAppear(perform: self.loadData)

                VStack {
                    Text("loading")
                    ActivityIndicator(isAnimating: self.store.state.category.loading, style: .large)
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary.colorInvert())
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(self.store.state.category.loading ? 1 : 0)
            }
        }
    }

    func loadData() {
        if self.store.state.category.categoryItems.count > 0 {
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
