//
// Created on 6/10/20.
//

import SwiftUI
import NotificationBannerSwift

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
                ArchiveList(archives: categoryArchiveListModel.result)
                        .onAppear {
                            categoryArchiveListModel.load(state: store.state)
                            if !categoryItem.archives.isEmpty {
                                categoryArchiveListModel.loadStaticCategory(ids: categoryItem.archives)
                            }
                        }
                        .task {
                            if !categoryItem.search.isEmpty
                                && (categoryItem.search != categoryArchiveListModel.keyword
                                    || categoryArchiveListModel.result.isEmpty) {
                                categoryArchiveListModel.keyword = categoryItem.search
                                await categoryArchiveListModel.loadDynamicCategory()
                            }
                        }
                        .onDisappear {
                            categoryArchiveListModel.reset()
                            categoryArchiveListModel.unload()
                        }
                        .onChange(of: categoryArchiveListModel.isError) { isError in
                            if isError {
                                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                        subtitle: categoryArchiveListModel.errorMessage,
                                        style: .danger)
                                banner.show()
                                categoryArchiveListModel.reset()
                            }
                        }
                if categoryArchiveListModel.isLoading {
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
                    .toolbar(.hidden, for: .tabBar)
        }
    }
}
