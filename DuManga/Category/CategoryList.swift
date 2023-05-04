import SwiftUI
import NotificationBannerSwift

struct CategoryList: View {
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    @State private var editMode: EditMode = .inactive

    @EnvironmentObject var store: AppStore

    @StateObject var categoryListModel = CategoryListModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                List(Array(categoryListModel.categoryItems.values
                    .sorted(by: { $0.name < $1.name }))) { item in
                    if editMode == .active {
                        HStack {
                            Text(item.name)
                                    .font(.title)
                            Spacer()
                            Image(systemName: "square.and.pencil")
                        }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    categoryListModel.selectedCategoryItem = item
                                    categoryListModel.showSheetView = true
                                }
                    } else {
                        NavigationLink(value: item) {
                            Text(item.name)
                                    .font(.title)
                        }
                    }
                }
                        .navigationDestination(for: CategoryItem.self) { item in
                            CategoryArchiveList(categoryItem: item)
                        }
                if !categoryListModel.isPullToRefresh && categoryListModel.loading {
                    VStack {
                        Text("loading")
                        ProgressView()
                    }
                            .frame(width: geometry.size.width / 3,
                                    height: geometry.size.height / 5)
                            .background(Color.secondary)
                            .foregroundColor(Color.primary)
                            .cornerRadius(20)
                }
            }
                    .toolbar {
                        EditButton()
                    }
                    .onAppear {
                        categoryListModel.load(state: store.state)
                    }
                    .onDisappear {
                        categoryListModel.unload()
                    }
                    .task {
                        if categoryListModel.categoryItems.count > 0 {
                            return
                        }
                        await store.dispatch(fetchCategory(fromServer: alwaysLoadFromServer))
                    }
                    .environment(\.editMode, $editMode)
                    .refreshable {
                        if categoryListModel.loading != true {
                            categoryListModel.isPullToRefresh = true
                            await store.dispatch(fetchCategory(fromServer: true))
                            categoryListModel.isPullToRefresh = false
                        }
                    }
                    .sheet(isPresented: $categoryListModel.showSheetView) {
                        EditCategory(item: categoryListModel.selectedCategoryItem!)
                    }
                    .onChange(of: categoryListModel.errorCode, perform: { code in
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
}
