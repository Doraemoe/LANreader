import Foundation
import Combine
import Logging

class PrefetchService {
    private static let logger = Logger(label: "PrefetchService")

    private static var _shared: PrefetchService?

    private static var cancellables: Set<AnyCancellable> = []

    let prefetchSubject = PassthroughSubject<String, Never>()

    public static var shared: PrefetchService {
        if _shared == nil {
            let service = LANraragiService.shared
            let database = AppDatabase.shared
            _shared = PrefetchService()

            _shared!.prefetchSubject
                .subscribe(on: DispatchQueue.global(qos: .userInteractive))
                .filter { id in
                    (try? database.existsArchiveImage(id)) != true
                }
                .flatMap { id in
                    service.prefetchArchivePage(page: id)
                        .validate()
                        .publishURL(queue: .global(qos: .userInteractive))
                        .result()
                        .map { result in
                            (id, result)
                        }
                }
                .receive(on: DispatchQueue.global(qos: .userInteractive))
                .sink(
                    receiveValue: { (id, result) in
                        switch result {
                        case let .success(url):
                            let thresholdValue = UserDefaults.standard.integer(
                                forKey: SettingsKey.compressImageThreshold
                            )
                            let threshold = CompressThreshold(rawValue: thresholdValue) ?? .never
                            resizeImage(url: url, threshold: threshold)
                            var archiveImage = ArchiveImage(id: id, image: url.path, lastUpdate: Date())
                            do {
                                try database.saveArchiveImage(&archiveImage)
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
        return _shared!
    }
}
