//
// Created on 6/10/20.
//

import SwiftUI

struct CategoryArchiveList: View {
    private static let newCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: true,
            initResult: [ArchiveItem]())
    private static let dynamicCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())
    private static let staticCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())

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
                        .onChange(of: categoryArchiveListModel.archiveItems, perform: { _ in
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
        if !categoryItem.search.isEmpty && categoryArchiveListModel.dynamicCategoryKeys.isEmpty {
            store.dispatch(.archive(action: .fetchArchiveDynamicCategory(keyword: self.categoryItem.search)))
        }
    }
}
