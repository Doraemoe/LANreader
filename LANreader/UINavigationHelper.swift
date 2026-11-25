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
    case let .element(id: readerID, action: .reader(.removeCacheSuccess)):
        guard case let .reader(readerState) = path[id: readerID] else { return }
        cleanDeletedArchiveFromStack(archiveId: readerState.currentArchiveId, cachedOnly: true, in: &path)
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

private func handleDetailsDeleted(
    id detailsID: StackElementID,
    in path: inout StackState<ArchiveFlowPath.State>
) {
    guard case let .details(detailsState) = path[id: detailsID] else { return }
    let archiveId = detailsState.archive.id
    let cachedOnly = detailsState.cached
    path.pop(from: detailsID)
    cleanDeletedArchiveFromStack(
        archiveId: archiveId,
        cachedOnly: cachedOnly,
        in: &path
    )
}

private func syncTankoubonMetadata(
    from detailsID: StackElementID,
    title: String,
    tags: String,
    in path: inout StackState<ArchiveFlowPath.State>
) {
    guard case let .details(sourceDetails) = path[id: detailsID],
          let tankoubonId = sourceDetails.tankoubonMetadata?.id else {
        return
    }

    for id in path.ids where id != detailsID {
        switch path[id: id] {
        case let .reader(readerState)
            where !readerState.cached && readerState.currentTankoubonDetails?.id == tankoubonId:
            path[id: id, case: \.reader]?.currentTankoubonDetails?.name = title
            path[id: id, case: \.reader]?.currentTankoubonDetails?.tags = tags
        case let .details(detailsState)
            where !detailsState.cached && detailsState.tankoubonMetadata?.id == tankoubonId:
            path[id: id, case: \.details]?.tankoubonMetadata?.name = title
            path[id: id, case: \.details]?.tankoubonMetadata?.tags = tags
        default:
            break
        }
    }
}

private func cleanDeletedArchiveFromStack(
    archiveId: String,
    cachedOnly: Bool,
    in path: inout StackState<ArchiveFlowPath.State>
) {
    for id in path.ids {
        switch path[id: id] {
        case let .reader(readerState) where readerState.cached == cachedOnly:
            if readerState.currentArchiveId == archiveId {
                path[id: id] = nil
            } else if readerState.allArchives[id: archiveId] != nil {
                path[id: id, case: \.reader]?.allArchives.remove(id: archiveId)
            }
        case let .details(detailsState)
            where detailsState.cached == cachedOnly && detailsState.archive.id == archiveId:
            path[id: id] = nil
        default:
            break
        }
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
