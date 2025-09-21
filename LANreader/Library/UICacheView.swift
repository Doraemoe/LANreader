import ComposableArchitecture
import SwiftUI
import UIKit

class UICacheViewController: UIViewController, UICollectionViewDelegate {
    private let store: StoreOf<CacheFeature>
    private let navigationHelper: NavigationHelper

    init(store: StoreOf<CacheFeature>, navigationHelper: NavigationHelper) {
        self.store = store
        self.navigationHelper = navigationHelper
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = String(localized: "cached")

        let hostingController = UIHostingController(
            rootView: CacheView(store: store)
                .environment(navigationHelper)
        )
        add(hostingController)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }
}
