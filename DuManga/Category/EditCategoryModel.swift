//
// Created on 2/10/20.
//

import Foundation
import Combine

class EditCategoryModel: ObservableObject {
    @Published var categoryName = ""
    @Published var searchKeyword = ""

    @Published private(set) var updateDynamicCategorySuccess: Bool = false
    @Published private(set) var errorCode: ErrorCode?

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState, name: String, keyword: String) {
        categoryName = name
        searchKeyword = keyword
        state.category.$updateDynamicCategorySuccess.receive(on: DispatchQueue.main)
                .assign(to: \.updateDynamicCategorySuccess, on: self)
                .store(in: &cancellable)

        state.category.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }
}
