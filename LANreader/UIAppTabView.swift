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

    init(store: StoreOf<AppFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let libraryNav = UINavigationController()
        let libraryNavHelper = NavigationHelper()
        libraryNavHelper.navigationController = libraryNav
        let libraryView = UILibraryListViewController(
            store: store.scope(state: \.library, action: \.library),
            navigationHelper: libraryNavHelper
        )
        libraryNav.viewControllers = [libraryView]
        libraryNav.tabBarItem = UITabBarItem(
            title: String(localized: "library"),
            image: UIImage(systemName: "books.vertical"),
            tag: 0
        )
        libraryNav.hidesBottomBarWhenPushed = true

        let categoryView = UICategoryListViewController(store: store.scope(state: \.category, action: \.category))
        let categoryNav = UINavigationController(rootViewController: categoryView)
        categoryNav.tabBarItem = UITabBarItem(
            title: String(localized: "category"),
            image: UIImage(systemName: "folder"),
            tag: 1
        )

        let searchView = UISearchViewController(store: store.scope(state: \.search, action: \.search))
        let searchNav = UINavigationController(rootViewController: searchView)
        searchNav.tabBarItem = UITabBarItem(
            title: String(localized: "search"),
            image: UIImage(systemName: "magnifyingglass"),
            tag: 2
        )

        let settingsNav = UINavigationController()
        let settingsNavHelper = NavigationHelper()
        settingsNavHelper.navigationController = settingsNav
        let settingsView = UISettingsViewController(
            store: store.scope(state: \.settings, action: \.settings),
            navigationHelper: settingsNavHelper
        )
        settingsNav.viewControllers = [settingsView]
        settingsNav.tabBarItem = UITabBarItem(
            title: String(localized: "settings"),
            image: UIImage(systemName: "gearshape"),
            tag: 3
        )
        settingsView.navigationItem.title = String(localized: "settings")

        self.viewControllers = [libraryNav, categoryNav, searchNav, settingsNav]
    }
}
