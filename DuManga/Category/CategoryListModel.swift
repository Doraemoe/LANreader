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

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState) {
        state.category.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellable)

        state.category.$categoryItems.receive(on: DispatchQueue.main)
                .assign(to: \.categoryItems, on: self)
                .store(in: &cancellable)

        state.category.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }
}
