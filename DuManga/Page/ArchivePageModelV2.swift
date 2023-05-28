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
    @Published private(set) var pages = [String]()
    @Published private(set) var errorCode: ErrorCode?
    @Published private(set) var deletedArchiveId = ""

    var verticalReaderReady = false

    private let service = LANraragiService.shared
    private let prefetch = PrefetchService.shared
    private let database = AppDatabase.shared
    private let store = AppStore.shared

    private var cancellables: Set<AnyCancellable> = []

    init() {
        loading = store.state.page.loading
        errorCode = store.state.page.errorCode
        deletedArchiveId = store.state.trigger.deletedArchiveId

        store.state.page.$loading.receive(on: DispatchQueue.main)
            .assign(to: \.loading, on: self)
            .store(in: &cancellables)

        store.state.page.$errorCode.receive(on: DispatchQueue.main)
            .assign(to: \.errorCode, on: self)
            .store(in: &cancellables)

        store.state.trigger.$deletedArchiveId.receive(on: DispatchQueue.main)
            .assign(to: \.deletedArchiveId, on: self)
            .store(in: &cancellables)
    }

    func load(id: String, progress: Int, startFromBeginning: Bool) {
        if currentIndex == 0 && !startFromBeginning {
            currentIndex = progress
        }

        pages = store.state.page.archivePages[id]!.wrappedValue
        store.state.page.archivePages[id]!.projectedValue.receive(on: DispatchQueue.main)
            .assign(to: \.pages, on: self)
            .store(in: &cancellables)
    }

    func prefetchImages(ids: [String], compressThreshold: CompressThreshold) {
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
        prefetch.preloadImages(ids: fetchArray, compressThreshold: compressThreshold)
    }

    func clearNewFlag(id: String) async {
        _ = try? await service.clearNewFlag(id: id).value
    }

    func addToHistory(id: String) {
        var history = History(id: id, lastUpdate: Date())
        try? database.saveHistory(&history)
    }
}
