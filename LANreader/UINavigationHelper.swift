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
    case let .element(id: id, action: .search(.archiveList(.openReader(archiveId, fromStart)))):
        guard case let .search(searchState) = path[id: id] else { return }
        let allArchives = searchState.archiveList.archivesToDisplay.map(\.$archive)
        path.append(
            .reader(
                ArchiveReaderFeature.State(
                    currentArchiveId: archiveId,
                    allArchives: allArchives,
                    fromStart: fromStart
                )
            )
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
        let normalizedTag = String(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        path.append(
            .search(
                SearchFeature.State(
                    keyword: normalizedTag,
                    archiveList: ArchiveListFeature.State(
                        filter: SearchFilter(category: nil, filter: normalizedTag),
                        loadOnAppear: true,
                        currentTab: .search
                    )
                )
            )
        )
    case let .element(id: detailsID, action: .details(.deleteSuccess)):
        guard let detailsIndex = path.ids.firstIndex(of: detailsID) else { return }
        if detailsIndex > path.ids.startIndex {
            let previousID = path.ids[path.ids.index(before: detailsIndex)]
            if case .reader = path[id: previousID] {
                path.pop(from: previousID)
                return
            }
        }
        path.pop(from: detailsID)
    default:
        break
    }
}

@MainActor
func makeArchiveFlowDestination(_ store: StoreOf<ArchiveFlowPath>) -> UIViewController {
    switch store.case {
    case let .reader(readerStore):
        UIArchiveReaderController(store: readerStore, usesStackNavigation: true)
    case let .details(detailsStore):
        UIHostingController(rootView: ArchiveDetailsV2(store: detailsStore))
    case let .search(searchStore):
        UISearchViewV2Controller(store: searchStore, usesStackNavigation: true)
    }
}
