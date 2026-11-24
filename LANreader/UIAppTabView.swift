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

class UITabViewController: UITabBarController, UITabBarControllerDelegate {
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
        delegate = self

        let libraryNav = makeLibraryNavigationController(
            store: store.scope(\.library, action: \.library)
        )
        libraryNav.tabBarItem = UITabBarItem(
            title: String(localized: "library"),
            image: UIImage(systemName: "books.vertical"),
            tag: TabName.library.tabIndex
        )

        let categoryNav = makeCategoryNavigationController(
            store: store.scope(\.category, action: \.category)
        )
        categoryNav.tabBarItem = UITabBarItem(
            title: String(localized: "category"),
            image: UIImage(systemName: "folder"),
            tag: TabName.category.tabIndex
        )

        let searchNav = makeSearchNavigationController(
            store: store.scope(\.search, action: \.search)
        )
        searchNav.tabBarItem = UITabBarItem(
            tabBarSystemItem: .search,
            tag: TabName.search.tabIndex
        )

        let settingsNav = makeSettingsNavigationController(
            store: store.scope(\.settings, action: \.settings)
        )
        settingsNav.tabBarItem = UITabBarItem(
            title: String(localized: "settings"),
            image: UIImage(systemName: "gearshape"),
            tag: TabName.settings.tabIndex
        )

        self.viewControllers = [libraryNav, categoryNav, searchNav, settingsNav]
        observeSelectedTab()
    }

    private func observeSelectedTab() {
        observe { [weak self] in
            guard let self else { return }
            let targetIndex = store.selectedTab.tabIndex
            if selectedIndex != targetIndex {
                selectedIndex = targetIndex
            }
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        guard let tab = TabName(tabIndex: selectedIndex),
              store.selectedTab != tab else { return }
        store.send(.selectTab(tab))
    }
}
