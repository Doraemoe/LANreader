import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer
public enum ArchiveFlowPath {
    case categoryArchives(CategoryArchiveListFeature)
    case cache(CacheFeature)
    case reader(ArchiveReaderFeature)
    case details(ArchiveDetailsFeature)
    case search(SearchFeature)
}

extension ArchiveFlowPath.State: Equatable {}

extension Reducer {
    /// Converts `.run` effects into Combine publisher effects so `StackReducer`'s
    /// `._cancellable(navigationIDPath:)` registers synchronously when an effect is returned and
    /// cuts off in-flight emissions synchronously when the stack element is popped.
    func synchronousCancellation() -> some ReducerOf<Self> {
        SynchronousCancellationReducer(base: self)
    }
}

private struct SynchronousCancellationReducer<Base: Reducer>: Reducer {
    let base: Base

    func reduce(into state: inout Base.State, action: Base.Action) -> Effect<Base.Action> {
        let effect = base.reduce(into: &state, action: action)
        return .publisher { _EffectPublisher(effect) }
    }
}

extension SynchronousCancellationReducer: Sendable where Base: Sendable {}

func reduceArchiveFlowPath(
    path: inout StackState<ArchiveFlowPath.State>,
    action: StackActionOf<ArchiveFlowPath>
) {
    switch action {
    case let .element(id: id, action: .categoryArchives(.archiveList(.openReader(archiveId, fromStart)))):
        guard case let .categoryArchives(categoryState) = path[id: id] else { return }
        appendReader(archiveId: archiveId, fromStart: fromStart, archiveList: categoryState.archiveList, to: &path)
    case let .element(id: id, action: .cache(.openReader(archiveId, fromStart))):
        guard case let .cache(cacheState) = path[id: id] else { return }
        appendCachedReader(archiveId: archiveId, fromStart: fromStart, cacheState: cacheState, to: &path)
    case let .element(id: id, action: .search(.archiveList(.openReader(archiveId, fromStart)))):
        guard case let .search(searchState) = path[id: id] else { return }
        appendReader(archiveId: archiveId, fromStart: fromStart, archiveList: searchState.archiveList, to: &path)
    case let .element(id: id, action: .reader(.openDetailsTapped)):
        guard case let .reader(readerState) = path[id: id] else { return }
        appendDetails(from: readerState, to: &path)
    case let .element(id: readerID, action: .reader(.finishDownloadPages)):
        guard case let .reader(readerState) = path[id: readerID] else { return }
        syncReaderCacheFlag(archiveId: readerState.currentArchiveId, inCache: true, excluding: readerID, in: &path)
    case let .element(id: readerID, action: .reader(.removeCacheSuccess)):
        guard case let .reader(readerState) = path[id: readerID] else { return }
        let archiveId = readerState.currentArchiveId
        if readerState.cached {
            path.pop(from: readerID)
        }
        cleanDeletedArchiveFromStack(archiveId: archiveId, cachedOnly: true, in: &path)
    case let .element(id: detailsID, action: .details(.updateLocalTankoubonMetadata(title, tags))):
        syncTankoubonMetadata(from: detailsID, title: title, tags: tags, in: &path)
    case let .element(id: _, action: .details(.tagTapped(tag))):
        path.append(.search(makeTagSearchState(for: tag)))
    case let .element(id: detailsID, action: .details(.deleteSuccess)):
        handleDetailsDeleted(id: detailsID, in: &path)
    default:
        break
    }
}

func appendReader(
    archiveId: String,
    fromStart: Bool,
    archiveList: ArchiveListFeature.State,
    to path: inout StackState<ArchiveFlowPath.State>
) {
    let allArchives = archiveList.archivesToDisplay.map(\.$archive)
    path.append(
        .reader(
            ArchiveReaderFeature.State(
                currentArchiveId: archiveId,
                allArchives: allArchives,
                fromStart: fromStart
            )
        )
    )
}

private func appendCachedReader(
    archiveId: String,
    fromStart: Bool,
    cacheState: CacheFeature.State,
    to path: inout StackState<ArchiveFlowPath.State>
) {
    let allArchives = cacheState.archives
        .filter { cacheState.downloading[$0.id] == nil }
        .map(\.$archive)
    path.append(
        .reader(
            ArchiveReaderFeature.State(
                currentArchiveId: archiveId,
                allArchives: allArchives,
                fromStart: fromStart,
                cached: true
            )
        )
    )
}

private func appendDetails(
    from readerState: ArchiveReaderFeature.State,
    to path: inout StackState<ArchiveFlowPath.State>
) {
    guard readerState.canOpenDetails,
          let currentArchive = readerState.allArchives[id: readerState.currentArchiveId] else {
        return
    }
    path.append(
        .details(
            ArchiveDetailsFeature.State(
                archive: currentArchive,
                cached: readerState.cached,
                tankoubonMetadata: readerState.currentTankoubonDetails
            )
        )
    )
}

private func makeTagSearchState(for tag: String) -> SearchFeature.State {
    let normalizedTag = String(tag.trimmingCharacters(in: .whitespacesAndNewlines))
    return SearchFeature.State(
        keyword: normalizedTag,
        archiveList: ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: normalizedTag),
            loadOnAppear: true,
            currentTab: .search
        )
    )
}

private func popArchiveDetails(
    id detailsID: StackElementID,
    from path: inout StackState<ArchiveFlowPath.State>
) {
    guard let detailsIndex = path.ids.firstIndex(of: detailsID) else { return }
    if detailsIndex > path.ids.startIndex {
        let previousID = path.ids[path.ids.index(before: detailsIndex)]
        if case .reader = path[id: previousID] {
            path.pop(from: previousID)
            return
        }
    }
    path.pop(from: detailsID)
}

private func handleDetailsDeleted(
    id detailsID: StackElementID,
    in path: inout StackState<ArchiveFlowPath.State>
) {
    let deletedTarget = path[id: detailsID].flatMap { element -> (id: String, cached: Bool)? in
        guard case let .details(detailsState) = element else { return nil }
        return (detailsState.archive.id, detailsState.cached)
    }
    popArchiveDetails(id: detailsID, from: &path)
    if let deletedTarget {
        cleanDeletedArchiveFromStack(
            archiveId: deletedTarget.id,
            cachedOnly: deletedTarget.cached,
            in: &path
        )
    }
}

private func syncTankoubonMetadata(
    from detailsID: StackElementID,
    title: String,
    tags: String,
    in path: inout StackState<ArchiveFlowPath.State>
) {
    guard case let .details(sourceDetails) = path[id: detailsID],
          let updatedMetadata = sourceDetails.tankoubonMetadata else {
        return
    }
    let tankoubonId = updatedMetadata.id
    let combinedTags = updatedMetadata.combinedTags

    for id in path.ids where id != detailsID {
        switch path[id: id] {
        case var .reader(readerState) where !readerState.cached:
            var changed = false
            if readerState.currentTankoubonDetails?.id == tankoubonId {
                readerState.currentTankoubonDetails?.name = title
                readerState.currentTankoubonDetails?.tags = tags
                changed = true
            }
            if let tankArchive = readerState.allArchives[id: tankoubonId] {
                tankArchive.withLock {
                    $0.name = title
                    $0.tags = combinedTags
                }
            }
            if changed {
                path[id: id] = .reader(readerState)
            }
        case var .details(detailsState)
            where !detailsState.cached && detailsState.tankoubonMetadata?.id == tankoubonId:
            detailsState.tankoubonMetadata?.name = title
            detailsState.tankoubonMetadata?.tags = tags
            detailsState.$archive.withLock {
                $0.name = title
                $0.tags = combinedTags
            }
            path[id: id] = .details(detailsState)
        default:
            break
        }
    }
}

private func syncReaderCacheFlag(
    archiveId: String,
    inCache: Bool,
    excluding excludedID: StackElementID,
    in path: inout StackState<ArchiveFlowPath.State>
) {
    for id in path.ids where id != excludedID {
        guard case var .reader(readerState) = path[id: id],
              !readerState.cached,
              readerState.currentArchiveId == archiveId,
              readerState.inCache != inCache else {
            continue
        }
        readerState.inCache = inCache
        path[id: id] = .reader(readerState)
    }
}

private func cleanDeletedArchiveFromStack(
    archiveId: String,
    cachedOnly: Bool,
    in path: inout StackState<ArchiveFlowPath.State>
) {
    var idsToRemove: Set<StackElementID> = []
    for id in path.ids {
        switch path[id: id] {
        case var .reader(readerState):
            if readerState.cached == cachedOnly {
                if readerState.currentArchiveId == archiveId {
                    idsToRemove.insert(id)
                } else if readerState.allArchives[id: archiveId] != nil {
                    readerState.allArchives.remove(id: archiveId)
                    path[id: id] = .reader(readerState)
                }
            } else if cachedOnly, !readerState.cached,
                      readerState.currentArchiveId == archiveId, readerState.inCache {
                readerState.inCache = false
                path[id: id] = .reader(readerState)
            }
        case let .details(detailsState):
            if detailsState.cached == cachedOnly, detailsState.archive.id == archiveId {
                idsToRemove.insert(id)
            }
        default:
            break
        }
    }
    guard !idsToRemove.isEmpty else { return }
    for index in path.ids.indices.reversed() where idsToRemove.contains(path.ids[index]) {
        path.remove(at: index)
    }
}

@MainActor
func makeArchiveFlowDestination(_ store: StoreOf<ArchiveFlowPath>) -> UIViewController {
    switch store.case {
    case let .categoryArchives(categoryStore):
        UICategoryArchiveGridController(store: categoryStore)
    case let .cache(cacheStore):
        UICacheViewController(store: cacheStore)
    case let .reader(readerStore):
        UIArchiveReaderController(store: readerStore)
    case let .details(detailsStore):
        UIHostingController(rootView: ArchiveDetailsV2(store: detailsStore))
    case let .search(searchStore):
        UISearchViewV2Controller(store: searchStore)
    }
}
