import ComposableArchitecture
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class NavigationHelper {
    weak var navigationController: UINavigationController?

    func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    func pop() {
        navigationController?.popViewController(animated: true)
    }
}

@Reducer
public enum ArchiveFlowPath {
    case categoryArchives(CategoryArchiveListFeature)
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
        appendReader(
            archiveId: archiveId,
            fromStart: fromStart,
            archiveList: categoryState.archiveList,
            to: &path
        )
    case let .element(id: id, action: .search(.archiveList(.openReader(archiveId, fromStart)))):
        guard case let .search(searchState) = path[id: id] else { return }
        appendReader(
            archiveId: archiveId,
            fromStart: fromStart,
            archiveList: searchState.archiveList,
            to: &path
        )
    case let .element(id: id, action: .reader(.openDetailsTapped)):
        guard case let .reader(readerState) = path[id: id],
              readerState.canOpenDetails,
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
    case let .element(id: _, action: .details(.tagTapped(tag))):
        path.append(.search(makeTagSearchState(for: tag)))
    case let .element(id: detailsID, action: .details(.deleteSuccess)):
        popArchiveDetails(id: detailsID, from: &path)
    default:
        break
    }
}

private func appendReader(
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
    case let .reader(readerStore):
        UIArchiveReaderController(store: readerStore, usesStackNavigation: true)
    case let .details(detailsStore):
        UIHostingController(rootView: ArchiveDetailsV2(store: detailsStore))
    case let .search(searchStore):
        UISearchViewV2Controller(store: searchStore, usesStackNavigation: true)
    }
}
