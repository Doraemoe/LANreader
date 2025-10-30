import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer public struct LibraryFeature {
    @ObservableState
    public struct State: Equatable {
        var archiveList = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            currentTab: .library
        )
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case archiveList(ArchiveListFeature.Action)
        case toggleSelectMode
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        Reduce { state, action in
            switch action {
            case .toggleSelectMode:
                if state.archiveList.selectMode == .inactive {
                    state.archiveList.selectMode = .active
                } else {
                    state.archiveList.selectMode = .inactive
                }
                return .none
            case .archiveList:
                return .none
            case .binding:
                return .none
            }
        }
    }
}

class UILibraryListViewController: UIViewController {
    let store: StoreOf<LibraryFeature>
    let navigationHelper: NavigationHelper

    init(store: StoreOf<LibraryFeature>, navigationHelper: NavigationHelper) {
        self.store = store
        self.navigationHelper = navigationHelper
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
        navigationItem.leftBarButtonItems = [cachedButton]
        navigationItem.title = String(localized: "library")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()

        let archiveListView = UIArchiveListViewController(
            store: store.scope(state: \.archiveList, action: \.archiveList)
        )
        add(archiveListView)
        NSLayoutConstraint.activate([
            archiveListView.view.topAnchor.constraint(equalTo: view.topAnchor),
            archiveListView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            archiveListView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            archiveListView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(false, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = false
        }
    }

    @objc private func tapCachedButton() {
        let cacheStore = Store(initialState: CacheFeature.State.init()) {
            CacheFeature()
        }
        let cacheController = UICacheViewController(store: cacheStore, navigationHelper: navigationHelper)
        navigationController?.pushViewController(cacheController, animated: true)

    }
}
