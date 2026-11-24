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
    case let .element(id: readerID, action: .reader(.removeCacheSuccess)):
        guard case let .reader(readerState) = path[id: readerID], readerState.cached else { return }
        path.pop(from: readerID)
    case let .element(id: _, action: .details(.tagTapped(tag))):
        path.append(.search(makeTagSearchState(for: tag)))
    case let .element(id: detailsID, action: .details(.deleteSuccess)):
        popArchiveDetails(id: detailsID, from: &path)
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
