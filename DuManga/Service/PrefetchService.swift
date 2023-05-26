import Foundation
import Combine
import Logging

class PrefetchService {
    private static let logger = Logger(label: "PrefetchService")

    private static var _shared: PrefetchService?

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared

    private var cancellables: Set<AnyCancellable> = []

    func preloadImages(ids: [String], compressThreshold: CompressThreshold) {
        ids.publisher
            .subscribe(on: DispatchQueue.global(qos: .background))
            .flatMap(maxPublishers: .max(2)) {
                Just($0).delay(for: .seconds(0.3), scheduler: RunLoop.main)
            }
            .filter { [self] id in
                (try? database.existsArchiveImage(id)) != true
            }
            .flatMap { id in
                self.service.fetchArchivePage(page: id)
                    .validate()
                    .publishData()
                    .result()
                    .map { result in
                        (id, result)
                    }
            }
            .receive(on: DispatchQueue.global(qos: .background))
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        PrefetchService.logger.error("Failed to prefetch \(error)")
                    case .finished:
                        return
                    }
                },
                receiveValue: { (id, result) in
                    switch result {
                    case let .success(data):
                        let dataToSave = resizeImage(data: data, threshold: compressThreshold)
                        var archiveImage = ArchiveImage(id: id, image: dataToSave, lastUpdate: Date())
                        do {
                            try self.database.saveArchiveImage(&archiveImage)
                        } catch {
                            PrefetchService.logger.warning(
                                "can't save prefetch image to db. pageId=\(id) \(error)"
                            )
                        }
                    case let .failure(error):
                        PrefetchService.logger.warning("failed to prefetch image. pageId=\(id) \(error)")
                    }
                })
            .store(in: &cancellables)
    }

    func unload() {
        cancellables.forEach({ $0.cancel() })
    }

    public static var shared: PrefetchService {
        if _shared == nil {
            _shared = PrefetchService()
        }
        return _shared!
    }
}
