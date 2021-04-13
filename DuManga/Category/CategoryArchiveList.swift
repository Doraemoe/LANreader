//
// Created on 6/10/20.
//

import SwiftUI

struct CategoryArchiveList: View {
    @EnvironmentObject var store: AppStore

    @StateObject private var categoryArchiveListModel = CategoryArchiveListModel()

    private let categoryItem: CategoryItem

    init(categoryItem: CategoryItem) {
        self.categoryItem = categoryItem
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: categoryArchiveListModel.filteredArchives)
                        .onAppear(perform: {
                            categoryArchiveListModel.load(state: store.state)
                            loadData()
                        })
                        .onChange(of: categoryArchiveListModel.dynamicCategoryKeys, perform: { _ in
                            categoryArchiveListModel.filterArchives(categoryItem: categoryItem)
                        })
                VStack {
                    Text("loading")
                    ProgressView()
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary)
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(categoryArchiveListModel.loading ? 1 : 0)
            }
        }
    }

    private func loadData() {
        if categoryItem.search.isEmpty {
            categoryArchiveListModel.filterArchives(categoryItem: categoryItem)
        } else if categoryArchiveListModel.dynamicCategoryKeys.isEmpty {
            store.dispatch(.archive(action: .fetchArchiveDynamicCategory))
            categoryArchiveListModel.loadDynamicCategoryKeys(keyword: categoryItem.search,
                    dispatch: { action in
                        store.dispatch(action)
                    })
        }
    }
}
