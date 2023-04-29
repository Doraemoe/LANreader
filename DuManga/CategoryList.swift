// Created 27/8/20

import SwiftUI
import NotificationBannerSwift

struct CategoryList: View {
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    @EnvironmentObject var store: AppStore
    @StateObject var categoryListModel = CategoryListModel()

    @Binding var editMode: EditMode

    init(editMode: Binding<EditMode>) {
        self._editMode = editMode
    }

    var body: some View {
        let categories = Array(categoryListModel.categoryItems.values).sorted(by: { $0.name < $1.name })
        return GeometryReader { geometry in
            ZStack {
                List(categories) { (item: CategoryItem) in
                    if self.editMode == .active {
                        HStack {
                            Text(item.name)
                                    .font(.title)
                            Spacer()
                        }
                                .contentShape(Rectangle())
                                .onTapGesture(perform: {
                                    categoryListModel.selectedCategoryItem = item
                                    categoryListModel.showSheetView = true
                                })
                    } else {
                        NavigationLink(destination: CategoryArchiveList(categoryItem: item)) {
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
                        .onAppear(perform: {
                            self.loadData()
                        })
                        .refreshable {
                            if categoryListModel.loading != true {
                                self.categoryListModel.isPullToRefresh = true
                                self.store.dispatch(.category(action: .fetchCategory(fromServer: true)))
                                await checkLoadingFinished()
                                self.categoryListModel.isPullToRefresh = false
                            }
                        }
                if !self.categoryListModel.isPullToRefresh && self.categoryListModel.loading {
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
        self.store.dispatch(.category(action: .fetchCategory(fromServer: alwaysLoadFromServer)))
    }

    private func checkLoadingFinished() async {
        repeat {
            try? await Task.sleep(for: Duration.seconds(1))
        }
        while categoryListModel.loading == true
    }
}

struct CategoryList_Previews: PreviewProvider {
    static var previews: some View {
        let config = ["url": "http://localhost", "apiKey": "apiKey"]
        UserDefaults.standard.set(config, forKey: "LANraragi")
        return CategoryList(editMode: Binding.constant(.active))
    }
}
