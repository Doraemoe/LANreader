import SwiftUI
import NotificationBannerSwift

struct CategoryList: View {
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    @State private var editMode: EditMode = .inactive

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
            .navigationTitle("category")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                categoryListModel.connectStore()
            }
            .onDisappear {
                categoryListModel.disconnectStore()
            }
            .toolbar {
                EditButton()
            }
            .task {
                if categoryListModel.categoryItems.isEmpty {
                    await categoryListModel.load(fromServer: alwaysLoadFromServer)
                }
            }
            .environment(\.editMode, $editMode)
            .refreshable {
                if categoryListModel.loading != true {
                    categoryListModel.isPullToRefresh = true
                    await categoryListModel.load(fromServer: true)
                    categoryListModel.isPullToRefresh = false
                }
            }
            .sheet(isPresented: $categoryListModel.showSheetView) {
                EditCategory(item: categoryListModel.selectedCategoryItem!)
            }
            .onChange(of: categoryListModel.errorCode) {
                if categoryListModel.errorCode != nil {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("error", comment: "error"),
                        subtitle: NSLocalizedString("error.category", comment: "category error"),
                        style: .danger
                    )
                    banner.show()
                    categoryListModel.reset()
                }
            }
        }
    }
}
