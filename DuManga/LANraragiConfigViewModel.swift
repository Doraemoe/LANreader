//
// Created on 2/10/20.
//

import Foundation
import Combine

class LANraragiConfigViewModel: ObservableObject {
    @Published var url = ""
    @Published var apiKey = ""
    @Published var isVerifying = false

    @Published private(set) var savedSuccess = false
    @Published private(set) var errorCode: ErrorCode?

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState) {
        self.url = state.setting.url
        self.apiKey = state.setting.apiKey

        state.setting.$savedSuccess.receive(on: DispatchQueue.main)
                .assign(to: \.savedSuccess, on: self)
                .store(in: &cancellable)

        state.setting.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }
}
