import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer public struct LibraryFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        var path = StackState<ArchiveFlowPath.State>()
        var archiveList = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            currentTab: .library
        )
    }

    public enum Action {
        case path(StackActionOf<ArchiveFlowPath>)
        case archiveList(ArchiveListFeature.Action)
        case cacheButtonTapped
        case openDeepLinkReader(ArchiveItem, cached: Bool)
    }

    public var body: some ReducerOf<Self> {
        Scope(\.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        Reduce { state, action in
            switch action {
            case .cacheButtonTapped:
                state.path.append(.cache(CacheFeature.State()))
                return .none
            case let .openDeepLinkReader(archive, cached):
                let sharedArchive = cached ? nil : Shared(state.archiveList.$archiveItems[id: archive.id])
                state.path.removeAll()
                state.path.append(
                    .reader(
                        ArchiveReaderFeature.State(
                            currentArchiveId: archive.id,
                            allArchives: [sharedArchive ?? Shared(value: archive)],
                            cached: cached
                        )
                    )
                )
                return .none
            case let .archiveList(.openReader(archiveId, fromStart)):
                appendReader(
                    archiveId: archiveId,
                    fromStart: fromStart,
                    archiveList: state.archiveList,
                    to: &state.path
                )
                return .none
            case let .path(pathAction):
                reduceArchiveFlowPath(path: &state.path, action: pathAction)
                return .none
            case .archiveList:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            ArchiveFlowPath.body.synchronousCancellation()
        }
    }
}

@MainActor
func makeLibraryNavigationController(
    store: StoreOf<LibraryFeature>
) -> NavigationStackController {
    @UIBindable var store = store
    return NavigationStackController(
        path: $store.scope(\.path, action: \.path),
        root: { UILibraryListViewController(store: store) },
        destination: makeArchiveFlowDestination
    )
}

class UILibraryListViewController: UIViewController {
    let store: StoreOf<LibraryFeature>

    init(store: StoreOf<LibraryFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupNavigationBar() {
        let cachedButton = UIBarButtonItem(
            image: UIImage(systemName: "arrowshape.down"),
            style: .plain,
            target: self,
            action: #selector(tapCachedButton)
        )
        navigationItem.leftBarButtonItems = store.archiveList.selectMode == .active ? [] : [cachedButton]
        navigationItem.title = String(localized: "library")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        observe { [weak self] in
            self?.setupNavigationBar()
        }

        let archiveListView = UIArchiveListViewController(
            store: store.scope(\.archiveList, action: \.archiveList)
        )
        add(archiveListView)
        NSLayoutConstraint.activate([
            archiveListView.view.topAnchor.constraint(equalTo: view.topAnchor),
            archiveListView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            archiveListView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            archiveListView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    @objc private func tapCachedButton() {
        store.send(.cacheButtonTapped)
    }
}
