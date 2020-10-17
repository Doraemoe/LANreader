//Created 17/10/20

import SwiftUI
import Combine
import Foundation

class ThumbnailImageModel: ObservableObject {
    private static let imageProcessingQueue = DispatchQueue(label: "image-processing")

    @Published var image = Image("placeholder")

    private(set) var isLoading = false

    private let id: String
    private let service = LANraragiService.shared
    private var cancellable: Set<AnyCancellable> = []

    init(id: String) {
        self.id = id
    }

    deinit {
        unload()
    }

    func load() {
        guard !isLoading else { return }

        service.retrieveArchiveThumbnail(id: id)
            .subscribe(on: Self.imageProcessingQueue)
            .map { Image(uiImage: $0) }
            .replaceError(with: Image("placeholder"))
            .handleEvents(receiveSubscription: {[weak self] _ in self?.onStart()},
                          receiveCompletion: {[weak self] _ in self?.onFinish() },
                          receiveCancel: {[weak self] in self?.onFinish() })
            .receive(on: DispatchQueue.main)
            .assign(to: \.image, on: self)
            .store(in: &cancellable)
    }

    func unload() {
        self.onFinish()
        cancellable.forEach({ $0.cancel() })
    }

    private func onStart() {
        isLoading = true
    }

    private func onFinish() {
        isLoading = false
    }
}
