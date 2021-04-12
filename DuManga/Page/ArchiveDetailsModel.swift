//
// Created on 3/10/20.
//

import Foundation
import Combine

class ArchiveDetailsModel: ObservableObject {

    @Published var title = ""
    @Published var tags = ""

    @Published private(set) var loading = false
    @Published private(set) var updateSuccess = false
    @Published private(set) var deleteSuccess = false
    @Published private(set) var errorCode: ErrorCode?

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState, title: String, tags: String) {
        self.title = title
        self.tags = tags

        state.archive.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellable)

        state.archive.$updateArchiveMetadataSuccess.receive(on: DispatchQueue.main)
                .assign(to: \.updateSuccess, on: self)
                .store(in: &cancellable)

        state.archive.$deleteArchiveSuccess.receive(on: DispatchQueue.main)
                .assign(to: \.deleteSuccess, on: self)
                .store(in: &cancellable)

        state.archive.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }
}
