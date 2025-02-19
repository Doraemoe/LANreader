import ComposableArchitecture
import SwiftUI
import UIKit

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
        let randomButton = UIBarButtonItem(
            image: UIImage(systemName: "shuffle"),
            style: .plain,
            target: self,
            action: #selector(tapRandomButton)
        )
        navigationItem.leftBarButtonItem = randomButton
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
        }
    }

    @objc private func tapRandomButton() {
        let randomStore = Store(initialState: RandomFeature.State.init()) {
            RandomFeature()
        }
        let randomController = UIRandomViewController(store: randomStore)
        randomController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(
            randomController,
            animated: true
        )
    }
}
