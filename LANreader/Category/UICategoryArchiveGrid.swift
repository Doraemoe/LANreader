import ComposableArchitecture
import SwiftUI
import UIKit

public struct UICategoryArchiveGrid: UIViewControllerRepresentable {
    let store: StoreOf<CategoryArchiveListFeature>

    public init(store: StoreOf<CategoryArchiveListFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        UICategoryArchiveGridController(store: store)
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
    }
}

class UICategoryArchiveGridController: UIViewController {
    let store: StoreOf<CategoryArchiveListFeature>

    init(store: StoreOf<CategoryArchiveListFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = store.name
        tabBarController?.tabBar.isHidden = true

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
        store.send(.setTabBarHidden(true))
    }
}
