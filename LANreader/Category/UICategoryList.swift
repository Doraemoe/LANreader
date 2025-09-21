import ComposableArchitecture
import SwiftUI
import UIKit

class UICategoryListViewController: UIViewController {
    private let store: StoreOf<CategoryFeature>
    private var hostingController: UIHostingController<CategoryListV2>!

    init(store: StoreOf<CategoryFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        self.hostingController = UIHostingController(rootView: CategoryListV2(store: store, onTapCategory: {store in
            let categoryController = UICategoryArchiveGridController(store: store)
            self.navigationController?.pushViewController(
                categoryController,
                animated: true
            )
        }))
        add(hostingController)
        NSLayoutConstraint.activate([
            hostingController!.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController!.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController!.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController!.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        navigationItem.title = String(localized: "category")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(false, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = false
        }
    }
}
