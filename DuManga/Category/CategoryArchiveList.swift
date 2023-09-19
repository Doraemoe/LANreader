//
// Created on 6/10/20.
//

import SwiftUI
import NotificationBannerSwift

struct CategoryArchiveList: View {
    @State private var categoryArchiveListModel = CategoryArchiveListModel()

    @State private var enableSelect: EditMode = .inactive

    private let categoryItem: CategoryItem

    init(categoryItem: CategoryItem) {
        self.categoryItem = categoryItem
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if enableSelect == .active {
                    ArchiveSelection(
                        archives: categoryArchiveListModel.loadCategory(),
                        archiveSelectFor: categoryItem.search.isEmpty ? .categoryStatic : .categoryDynamic,
                        categoryId: categoryItem.id
                    )
                } else {
                    ArchiveList(archives: categoryArchiveListModel.loadCategory())
                        .task {
                            if categoryItem.search.isEmpty {
                                categoryArchiveListModel.loadStaticCategory(id: categoryItem.id)
                            } else {
                                await categoryArchiveListModel.loadDynamicCategory(keyword: categoryItem.search)
                            }
                        }
                        .onDisappear {
                            categoryArchiveListModel.reset()
                        }
                        .onChange(of: categoryArchiveListModel.isError) {
                            if categoryArchiveListModel.isError {
                                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                                                subtitle: categoryArchiveListModel.errorMessage,
                                                                style: .danger)
                                banner.show()
                                categoryArchiveListModel.reset()
                            }
                        }
                }
                if categoryArchiveListModel.isLoading {
                    LoadingView(geometry: geometry)
                }
            }
            .onAppear {
                categoryArchiveListModel.connectStore()
            }
            .onDisappear {
                categoryArchiveListModel.disconnectStore()
            }
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(enableSelect == .active ? "cancel" : "select") {
                        switch enableSelect {
                        case .active:
                            self.enableSelect = .inactive
                        case .inactive:
                            self.enableSelect = .active
                        default:
                            break
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(categoryItem.name)
            .environment(\.editMode, $enableSelect)
            .onChange(of: categoryArchiveListModel.categoryItems[categoryItem.id]) { oldCategory, newCategory in
                if oldCategory?.archives != newCategory?.archives {
                    categoryArchiveListModel.loadStaticCategory(id: categoryItem.id)
                }
            }
        }
    }
}
