//
// Created on 6/10/20.
//

import Foundation
import Combine

@Observable
class LibraryListModel {
    var searchText = ""

    private(set) var loading = false
    private(set) var archiveItems = [String: ArchiveItem]()
    private(set) var errorCode: ErrorCode?

    private var cancellable: Set<AnyCancellable> = []

    private let store = AppStore.shared

    init() {
        connectStore()
    }

    func connectStore() {
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

    func disconnectStore() {
        cancellable.forEach { $0.cancel() }
    }

    func load(fromServer: Bool) async {
        await store.dispatch(fetchArchives(fromServer, isPullToRefrsh: false))
    }

    func resetArchiveState() {
        store.dispatch(.archive(action: .resetState))
    }

    func refresh(isPullToRefrsh: Bool) async {
        await store.dispatch(fetchArchives(true, isPullToRefrsh: isPullToRefrsh))
        store.dispatch(.archive(
            action: .setRandomOrderSeed(seed: UInt64.random(in: 1..<10000))
        ))
    }
}
