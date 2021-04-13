//
// Created on 6/10/20.
//

import SwiftUI

struct SearchResult: View {
    @EnvironmentObject var store: AppStore

    @StateObject private var searchResultModel = SearchResultModel()

    private let keyword: String

    init(keyword: String) {
        self.keyword = keyword
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: searchResultModel.filteredArchives)
                        .onAppear(perform: {
                            searchResultModel.load(state: store.state)
                            loadData()
                        })
                        .onChange(of: searchResultModel.searchResultKeys, perform: { _ in
                            searchResultModel.filterArchives()
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
                        .opacity(searchResultModel.loading ? 1 : 0)
            }
        }
    }

    private func loadData() {
        if !keyword.isEmpty {
            store.dispatch(.archive(action: .fetchArchiveDynamicCategory))
            searchResultModel.loadSearchResultKeys(keyword: keyword,
                    dispatch: { action in
                        store.dispatch(action)
                    })
        }
    }

}
