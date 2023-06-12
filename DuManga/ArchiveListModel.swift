import Foundation
import Combine

class ArchiveListModel: ObservableObject {

    @Published private(set) var randomSeed: UInt64 = 1

    private var sortedArchives = [String: [ArchiveItem]]()
    private var cancellables: Set<AnyCancellable> = []
    private let store = AppStore.shared

    init() {
        connectStore()
    }

    func connectStore() {
        randomSeed = store.state.archive.randomOrderSeed

        store.state.archive.$randomOrderSeed.receive(on: DispatchQueue.main)
                .assign(to: \.randomSeed, on: self)
                .store(in: &cancellables)
    }

    func disconnectStore() {
        cancellables.forEach { $0.cancel() }
    }

    func refreshThumbnail(id: String) {
        store.dispatch(.trigger(action: .thumbnailRefreshAction(id: id)))
    }

    func resetSortedArchives() {
        sortedArchives = .init()
    }

    func processArchives(
        archives: [ArchiveItem],
        sortOrder: String,
        hideRead: Bool,
        sortArchives: Bool
    ) -> [ArchiveItem] {
        if !sortArchives {
            return archives
        }

        var archivesToProcess: [ArchiveItem]
        let existingArchives = sortedArchives[sortOrder]
        if existingArchives?.isEmpty == false {
            archivesToProcess = existingArchives!
        } else {
            archivesToProcess = archives
            if sortOrder == ArchiveListOrder.name.rawValue {
                archivesToProcess = archivesToProcess.sorted(by: { $0.name < $1.name })
            } else if sortOrder == ArchiveListOrder.dateAdded.rawValue {
                archivesToProcess = archivesToProcess.sorted { item, item2 in
                    let dateAdded1 = item.dateAdded
                    let dateAdded2 = item2.dateAdded
                    if dateAdded1 != nil && dateAdded2 != nil {
                        return dateAdded1! > dateAdded2!
                    } else if dateAdded1 != nil {
                        return true
                    } else if dateAdded2 != nil {
                        return false
                    } else {
                        return item.name < item2.name
                    }
                }

            } else if sortOrder == ArchiveListOrder.random.rawValue {
                var generator = FixedRandomGenerator(seed: randomSeed)
                archivesToProcess = archivesToProcess.shuffled(using: &generator)
            }
            sortedArchives[sortOrder] = archivesToProcess
        }

        if hideRead {
            archivesToProcess = archivesToProcess.filter { item in
                item.pagecount != item.progress
            }
        }
        var seenId = Set<String>()
        var distinctArchives = [ArchiveItem]()

        archivesToProcess.forEach { item in
            let (success, _) = seenId.insert(item.id)
            if success {
                distinctArchives.append(item)
            }
        }
        return distinctArchives
    }
}
