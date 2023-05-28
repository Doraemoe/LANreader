//
// Created on 1/10/20.
//

import Foundation
import Combine

class CategoryListModel: ObservableObject {
    @Published var showSheetView = false
    @Published var isPullToRefresh = false
    @Published var selectedCategoryItem: CategoryItem?

    @Published private(set) var loading = false
    @Published private(set) var categoryItems = [String: CategoryItem]()
    @Published private(set) var errorCode: ErrorCode?

    private let store = AppStore.shared

    private var cancellable: Set<AnyCancellable> = []

    init() {
        loading = store.state.category.loading
        categoryItems = store.state.category.categoryItems
        errorCode = store.state.category.errorCode

        store.state.category.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellable)

        store.state.category.$categoryItems.receive(on: DispatchQueue.main)
                .assign(to: \.categoryItems, on: self)
                .store(in: &cancellable)

        store.state.category.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func load(fromServer: Bool) async {
        await store.dispatch(fetchCategory(fromServer: fromServer))
    }

    func reset() {
        store.dispatch(.category(action: .resetState))
    }
}
