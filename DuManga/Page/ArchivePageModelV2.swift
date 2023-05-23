//
// Created on 14/4/21.
//

import Foundation
import Combine

class ArchivePageModelV2: ObservableObject {
    @Published var currentIndex = 0
    @Published var controlUiHidden = true
    @Published var sliderIndex: Double = 0.0

    @Published private(set) var loading = false
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var archivePages = [String: [String]]()
    @Published private(set) var errorCode: ErrorCode?

    var verticalReaderReady = false

    private let service = LANraragiService.shared
    private let prefetch = PrefetchService.shared
    private let database = AppDatabase.shared

    private var cancellables: Set<AnyCancellable> = []

    func load(state: AppState, progress: Int) {
        if currentIndex == 0 {
            currentIndex = progress
        }

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

    func prefetchImages(ids: [String]) {
        var firstHalf = ids[..<currentIndex].reversed().makeIterator()
        var secondHalf = ids[currentIndex...].dropFirst().makeIterator()
        var nextPage = secondHalf.next()
        var previousPage = firstHalf.next()
        var fetchArray = [String]()

        while  nextPage != nil || previousPage != nil {
            if nextPage != nil {
                fetchArray.append(nextPage!)
                nextPage = secondHalf.next()
            }
            if previousPage != nil {
                fetchArray.append(previousPage!)
                previousPage = firstHalf.next()
            }
        }
        prefetch.preloadImages(ids: fetchArray)
    }

    func clearNewFlag(id: String) async {
        _ = try? await service.clearNewFlag(id: id).value
    }

    func addToHistory(id: String) {
        var history = History(id: id, lastUpdate: Date())
        do {
            try database.saveHistory(&history)
        } catch {
            print("\(error)")
        }
    }
}
