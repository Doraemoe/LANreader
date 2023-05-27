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

    private let store = AppStore.shared

    init() {
        loading = store.state.archive.loading
        archiveItems = store.state.archive.archiveItems
        errorCode = store.state.archive.errorCode

        store.state.archive.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellable)

        store.state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellable)

        store.state.archive.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func load(fromServer: Bool) async {
        await store.dispatch(fetchArchives(fromServer))
    }

    func resetArchiveState() {
        store.dispatch(.archive(action: .resetState))
    }

    func refresh() async {
        await store.dispatch(fetchArchives(true))
        store.dispatch(.archive(
            action: .setRandomOrderSeed(seed: UInt64.random(in: 1..<10000))
        ))
    }
}
