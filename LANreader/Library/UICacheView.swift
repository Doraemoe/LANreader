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
        observe { [weak self] in
            guard let self else { return }
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: store.isSelecting ? String(localized: "done") : String(localized: "select"),
                primaryAction: UIAction { [weak self] _ in
                    self?.store.send(.toggleSelectionMode)
                }
            )
            let delete = UIBarButtonItem(
                image: UIImage(systemName: "trash"), style: .plain,
                target: self, action: #selector(confirmRemoval(_:))
            )
            delete.tintColor = .systemRed
            delete.accessibilityLabel = String(localized: "archive.cache.remove")
            delete.isEnabled = !store.selected.isEmpty
            toolbarItems = [.selectionCount(store.selected.count), .flexibleSpace(), delete]
            if navigationController?.topViewController === self {
                navigationController?.setToolbarHidden(!store.isSelecting, animated: false)
            }
        }

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
        navigationController?.setToolbarHidden(!store.isSelecting, animated: false)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: false)
    }

    @objc private func confirmRemoval(_ sender: UIBarButtonItem) {
        let alert = UIAlertController(
            title: String(localized: "archive.selected.delete"), message: nil, preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: String(localized: "archive.cache.remove"), style: .destructive
        ) { [weak self] _ in
            self?.store.send(.removeSelected)
        })
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        alert.popoverPresentationController?.barButtonItem = sender
        present(alert, animated: true)
    }
}

extension UIBarButtonItem {
    static func selectionCount(_ count: Int) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: String(format: String(localized: "archive.selected"), count),
            style: .plain, target: nil, action: nil
        )
        item.accessibilityTraits = .staticText
        return item
    }
}
