import ComposableArchitecture
import UIKit
import SwiftUI

public struct UIAppTabView: UIViewControllerRepresentable {
    let store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> some UIViewController {
        UITabViewController(store: store)
    }

    public func updateUIViewController(
        _ uiViewController: UIViewControllerType,
        context: Context
    ) {
        // Nothing to do
    }

}

class UITabViewController: UITabBarController {
    private let store: StoreOf<AppFeature>
    private var libraryNav: UINavigationController?
    private var searchNav: UINavigationController?
    private var searchView: UISearchViewV2Controller?

    init(store: StoreOf<AppFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let libraryNav = makeLibraryNavigationController(
            store: store.scope(\.library, action: \.library)
        )
        libraryNav.tabBarItem = UITabBarItem(
            title: String(localized: "library"),
            image: UIImage(systemName: "books.vertical"),
            tag: 0
        )

        let categoryNav = makeCategoryNavigationController(
            store: store.scope(\.category, action: \.category)
        )
        categoryNav.tabBarItem = UITabBarItem(
            title: String(localized: "category"),
            image: UIImage(systemName: "folder"),
            tag: 1
        )

        let (searchNav, searchView) = makeSearchNavigationController(
            store: store.scope(\.search, action: \.search)
        )
        searchNav.tabBarItem = UITabBarItem(
            tabBarSystemItem: .search,
            tag: 2
        )

        let settingsNav = makeSettingsNavigationController(
            store: store.scope(\.settings, action: \.settings)
        )
        settingsNav.tabBarItem = UITabBarItem(
            title: String(localized: "settings"),
            image: UIImage(systemName: "gearshape"),
            tag: 3
        )

        self.viewControllers = [libraryNav, categoryNav, searchNav, settingsNav]
        self.libraryNav = libraryNav
        self.searchNav = searchNav
        self.searchView = searchView
        observeDeepLinks()
    }

    private func observeDeepLinks() {
        observe { [weak self] in
            guard let self,
                  let route = store.pendingDeepLink,
                  store.destination == nil else { return }
            open(route)
            store.send(.deepLinkHandled)
        }
    }

    private func open(_ route: DeepLinkRoute) {
        switch route {
        case let .reader(archive, cached):
            guard let libraryNav else { return }
            selectedViewController = libraryNav
            store.send(.openDeepLinkReader(archive, cached: cached))
        case let .search(query):
            guard let searchNav else { return }
            selectedViewController = searchNav
            searchView?.showSearch(keyword: query)
        }
    }
}
