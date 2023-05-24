//
// Created on 6/10/20.
//

import Foundation
import Combine

class LibraryListModel: ObservableObject {
    @Published var isPullToRefresh = false
    @Published var searchText = ""

    @Published private(set) var loading = false
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var errorCode: ErrorCode?

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState) {
        loading = state.archive.loading
        archiveItems = state.archive.archiveItems
        errorCode = state.archive.errorCode

        state.archive.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellable)

        state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellable)

        state.archive.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }
}
