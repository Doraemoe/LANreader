//
// Created by Yifan Jin on 16/4/21.
// Copyright (c) 2021 Jin Yifan. All rights reserved.
//

import Foundation
import Combine
import Logging

class PrefetchService {
    private static let imageProcessingQueue = DispatchQueue(label: "image-processing")
    private static let logger = Logger(label: "PrefetchService")

    private static var _shared: PrefetchService?

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared

    private var isLoading = false
    private var fetchedIds = [String]()
    private var cancellables: Set<AnyCancellable> = []

    func preloadImages(ids: [String]) {
        guard !isLoading else {
            return
        }

        ids.publisher
                .subscribe(on: Self.imageProcessingQueue)
                .filter { output in
                    !self.fetchedIds.contains(output)
                }
                .flatMap(maxPublishers: .max(1)) {
                    Just($0).delay(for: .seconds(0.3), scheduler: RunLoop.main)
                }
                .handleEvents(receiveSubscription: { [weak self] _ in self?.onStart() },
                        receiveCompletion: { [weak self] _ in self?.onFinish() },
                        receiveCancel: { [weak self] in self?.onFinish() })
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        PrefetchService.logger.error("Error \(error)")
                    case .finished:
                        return
                    }
                },
                        receiveValue: { output in self.downloadImage(id: output) })
                .store(in: &cancellables)
    }

    func unload() {
        onFinish()
        cancellables.forEach({ $0.cancel() })
    }

    private func downloadImage(id: String) {
        service.fetchArchivePageData(page: id)
                .subscribe(on: Self.imageProcessingQueue)
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        PrefetchService.logger.error("Error \(error)")
                    case .finished:
                        return
                    }
                }, receiveValue: {
                    var archiveImage = ArchiveImage(id: id, image: $0, lastUpdate: Date())
                    do {
                        try self.database.saveArchiveImage(&archiveImage)
                        self.fetchedIds.append(id)
                    } catch {
                        PrefetchService.logger.error("db error. pageId=\(id) \(error)")
                    }
                })
                .store(in: &cancellables)
    }

    private func onStart() {
        isLoading = true
    }

    private func onFinish() {
        isLoading = false
    }

    public static var shared: PrefetchService {
        if _shared == nil {
            _shared = PrefetchService()
        }
        return _shared!
    }
}
