//
// Created on 6/10/20.
//

import SwiftUI

struct SearchResult: View {
    private static let searchResultSelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())

    @EnvironmentObject var store: AppStore

    @StateObject private var searchResultModel = SearchResultModel()

    private let keyword: String

    init(keyword: String) {
        self.keyword = keyword
    }

    var body: some View {
        let archives = selectArchives()
        return GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: archives)
                        .onAppear(perform: {
                            self.searchResultModel.load(state: store.state)
                            self.loadData()
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
                        .opacity(self.searchResultModel.loading ? 1 : 0)
            }
        }
    }

    private func loadData() {
        if !self.keyword.isEmpty {
            self.store.dispatch(.archive(action: .fetchArchiveDynamicCategory(keyword: self.keyword)))
        }
    }

    private func selectArchives() -> [ArchiveItem] {
        if !self.keyword.isEmpty {
            return SearchResult.searchResultSelector.select(
                    base: self.searchResultModel.archiveItems,
                    filter: self.searchResultModel.dynamicCategoryKeys,
                    selector: { (base, filter) in
                        let filtered = base.filter { item in
                            filter.contains(item.key)
                        }
                        return Array(filtered.values)
                    })
        } else {
            return [ArchiveItem]()
        }
    }
}
