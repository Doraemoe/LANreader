//
// Created by Yifan Jin on 14/4/21.
// Copyright (c) 2021 Jin Yifan. All rights reserved.
//

import Foundation
import Combine

class ArchivePageModelV2: ObservableObject {
    @Published var currentIndex: Double = 0.0
    @Published var controlUiHidden = true

    @Published private(set) var loading = false
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var archivePages = [String: [String]]()
    @Published private(set) var errorCode: ErrorCode?

    private var cancellables: Set<AnyCancellable> = []

    func load(state: AppState) {
        loading = state.page.loading
        archiveItems = state.archive.archiveItems
        archivePages = state.page.archivePages
        errorCode = state.page.errorCode

        state.page.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellables)

        state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellables)

        state.page.$archivePages.receive(on: DispatchQueue.main)
                .assign(to: \.archivePages, on: self)
                .store(in: &cancellables)

        state.page.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellables)
    }

    func unload() {
        cancellables.forEach({ $0.cancel() })
    }

    func verifyArchiveExists(id: String) -> Bool {
        archiveItems[id] != nil
    }
}
