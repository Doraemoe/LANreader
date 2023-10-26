import ComposableArchitecture
import Logging

struct ArchiveFeature: Reducer {
    private let logger = Logger(label: "ArchiveFeature")
    private let excludeTags = ["date_added", "source"]
    
    struct State: Equatable {
        var showLoading = true
        var archiveItems = [String: ArchiveItem]()
        var randomOrderSeed = UInt64.random(in: 1..<10000)
        var errorCode: ErrorCode?
    }
    
    enum Action: Equatable {
        case fetchArchives(Bool, Bool)
        case populateArchives([ArchiveIndexResponse], ErrorCode?)
        case updateArchive(ArchiveItem)
        case updateReadProgress(String, Int)
        case removeDeletedArchive(String)
        case setRandomOrderSeed(UInt64)
        case clearArchive
        case error(ErrorCode)
        case resetState
     }
    
    @Dependency(\.continuousClock) var clock
    @Dependency(\.lanraragiService) var lanraragiService
    @Dependency(\.appDatabase) var database
    
    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action{
        case let .fetchArchives(fromServer, showLoading):
            state.showLoading = showLoading
            if !fromServer {
                do {
                    let archives = try database.readAllArchive()
                    state.archiveItems = archives.reduce(into: [String: ArchiveItem]()) {
                        $0[$1.id] = $1.toArchiveItem()
                    }
                    state.showLoading = false
                } catch {
                    logger.warning("failed to read archive from db. \(error)")
                    state.errorCode = .archiveFetchError
                }
                return .none
            }
            return .run { send in
                do {
                    let archives = try await lanraragiService.retrieveArchiveIndex().value
                    await send(.populateArchives(archives, nil))
                } catch {
                    logger.error("failed to fetch archive. \(error)")
                    await send(.populateArchives([], .archiveFetchError))
                }
            }
        case let .populateArchives(archives, errorCode):
            if errorCode == nil {
                state.archiveItems = archives.reduce(into: [String: ArchiveItem]()) {
                    do {
                        var archive = $1.toArchive()
                        try database.saveArchive(&archive)
                    } catch {
                        logger.error("failed to save archive to db. id=\($1.arcid) \(error)")
                    }
                    $0[$1.arcid] = $1.toArchiveItem()
                }
            } else {
                state.errorCode = errorCode
            }
            state.showLoading = false
            return .run { send in
                Task.detached(priority: .background) {
                    try? await clock.sleep(for: .seconds(10))
                    _ = try? database.deleteAllTag()
                    let archives = try? database.readAllArchive()
                    archives?.forEach { archive in
                        archive.tags.forEach { tag in
                            let tagKey = String(tag.split(separator: ":").first ?? "")
                            if !excludeTags.contains(tagKey) {
                                var tagItem = TagItem(tag: tag)
                                try? database.saveTag(tagItem: &tagItem)
                            }
                        }
                    }
                }
            }
        case let .updateArchive(archive):
            state.archiveItems[archive.id] = archive
            var dbArchive = archive.toArchive()
            try? database.saveArchive(&dbArchive)
            return .run { send in
                Task.detached(priority: .background) {
                    try? await clock.sleep(for: .seconds(10))
                    let tagList = archive.tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    tagList.forEach { tag in
                        var tagItem = TagItem(tag: tag)
                        try? database.saveTag(tagItem: &tagItem)
                    }
                }
            }
        case let .updateReadProgress(id, progress):
            state.archiveItems[id]?.progress = progress
            _ = try? database.updateArchiveProgress(id, progress: progress)
            return .run { _ in
                _ = try? await lanraragiService.updateArchiveReadProgress(id: id, progress: progress).value
            }
        case let .removeDeletedArchive(id):
            state.archiveItems.removeValue(forKey: id)
            _ = try? database.deleteArchive(id)
            return .none
        case let .setRandomOrderSeed(seed):
            state.randomOrderSeed = seed
            return .none
        case .clearArchive:
            state.archiveItems = .init()
            return .none
        case let .error(error):
            state.showLoading = false
            state.errorCode = error
            return .none
        case .resetState:
            state.errorCode = nil
            return .none
        }
    }
}
