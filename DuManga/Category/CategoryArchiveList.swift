//
// Created on 6/10/20.
//

import SwiftUI

struct CategoryArchiveList: View {
    private static let dynamicCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [String: ArchiveItem]())
    private static let staticCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [String: ArchiveItem]())

    @EnvironmentObject var store: AppStore

    @StateObject private var categoryArchiveListModel = CategoryArchiveListModel()

    private let categoryItem: CategoryItem

    init(categoryItem: CategoryItem) {
        self.categoryItem = categoryItem
    }

    var body: some View {
        let archives = selectArchives()
        return GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: archives)
                        .onAppear(perform: {
                            self.categoryArchiveListModel.load(state: store.state)
                            self.loadData()
                        })
                        .onDisappear(perform: {
                            self.categoryArchiveListModel.unload()
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
                        .opacity(self.categoryArchiveListModel.loading ? 1 : 0)
            }
        }
    }

    private func loadData() {
        if !self.categoryItem.search.isEmpty {
            self.store.dispatch(.archive(action: .fetchArchiveDynamicCategory(keyword: self.categoryItem.search)))
        }
    }

    private func selectArchives() -> [String: ArchiveItem] {
        if !self.categoryItem.search.isEmpty {
            return CategoryArchiveList.dynamicCategorySelector.select(
                    base: self.categoryArchiveListModel.archiveItems,
                    filter: self.categoryArchiveListModel.dynamicCategoryKeys,
                    selector: { (base, filter) in
                        base.filter { item in
                            filter.contains(item.key)
                        }
                    })

        } else {
            return CategoryArchiveList.staticCategorySelector.select(
                    base: self.categoryArchiveListModel.archiveItems,
                    filter: self.categoryItem.archives,
                    selector: { (base, filter) in
                        base.filter { item in
                            filter.contains(item.key)
                        }
                    })
        }
    }
}
