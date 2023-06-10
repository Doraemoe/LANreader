//
// Created on 14/4/21.
//

import Foundation
import Combine
import Logging

class ArchivePageModelV2: ObservableObject {
    private static let logger = Logger(label: "ArchivePageModel")
    private static let prefetchNumber = 2

    @Published var currentIndex = 0
    @Published var controlUiHidden = true
    @Published var sliderIndex: Double = 0.0
    @Published var errorMessage = ""

    @Published private(set) var loading = false
    @Published private(set) var pages = [String]()
    @Published private(set) var deletedArchiveId = ""

    var verticalReaderReady = false

    private let service = LANraragiService.shared
    private let prefetch = PrefetchService.shared
    private let database = AppDatabase.shared
    private let store = AppStore.shared

    private var prefetchRequested: Set<String> = .init()
    private var cancellables: Set<AnyCancellable> = .init()

    init() {
        connectStore()
    }

    func connectStore() {
        deletedArchiveId = store.state.trigger.deletedArchiveId

        store.state.trigger.$deletedArchiveId.receive(on: DispatchQueue.main)
            .assign(to: \.deletedArchiveId, on: self)
            .store(in: &cancellables)
    }

    func disconnectStore() {
        cancellables.forEach { $0.cancel() }
    }

    func load(progress: Int, startFromBeginning: Bool) {
        if currentIndex == 0 && !startFromBeginning {
            currentIndex = progress
        }
    }

    @MainActor
    func extractArchive(id: String) async {
        if let storedPages = store.state.page.archivePages[id] {
            self.pages = storedPages
        } else {
            loading = true
            do {
                let extractResponse = try await service.extractArchive(id: id).value
                if extractResponse.pages.isEmpty {
                    ArchivePageModelV2.logger.error("server returned empty pages. id=\(id)")
                    errorMessage = NSLocalizedString("error.page.empty", comment: "empty content")
                } else {
                    var allPages = [String]()
                    extractResponse.pages.forEach { page in
                        let normalizedPage = String(page.dropFirst(2))
                        allPages.append(normalizedPage)
                    }
                    self.pages = allPages
                    store.dispatch(.page(action: .storeExtractedArchive(id: id, pages: allPages)))
                }
            } catch {
                ArchivePageModelV2.logger.error("failed to extract archive page. id=\(id) \(error)")
                self.errorMessage = error.localizedDescription
            }
            loading = false
        }
    }

    func prefetchImages() {
        var ids = [String]()
        for page in 1...ArchivePageModelV2.prefetchNumber where currentIndex + page < pages.count {
            ids.append(pages[currentIndex + page])
            if currentIndex - page > 0 {
                ids.append(pages[currentIndex - page])
            }
        }

        ids.filter { id in
            let (notExists, _) = prefetchRequested.insert(id)
            return notExists
        }.forEach { id in
            prefetch.prefetchSubject.send(id)
        }
    }

    func clearNewFlag(id: String) async {
        _ = try? await service.clearNewFlag(id: id).value
    }

    func addToHistory(id: String) {
        var history = History(id: id, lastUpdate: Date())
        try? database.saveHistory(&history)
    }

    func setCurrentPageAsThumbnail(id: String) async -> String {
        do {
            _ = try await service.updateArchiveThumbnail(id: id, page: currentIndex + 1).value
            store.dispatch(.trigger(action: .thumbnailRefreshAction(id: id)))
            return ""
        } catch {
            ArchivePageModelV2.logger.error("Failed to set current page as thumbnail. id=\(id) \(error)")
            return error.localizedDescription
        }
    }

    func resetError() {
        self.errorMessage = ""
    }
}
