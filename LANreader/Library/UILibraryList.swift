import ComposableArchitecture
import SwiftUI
import UIKit

public struct UILibraryList: UIViewControllerRepresentable {
    let store: StoreOf<LibraryFeature>

    public init(store: StoreOf<LibraryFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        UINavigationController(rootViewController: UILibraryListViewController(store: store))
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
    }
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

    override func viewDidLoad() {
        super.viewDidLoad()

        let archiveListView = UIArchiveListViewController(
            store: store.scope(state: \.archiveList, action: \.archiveList)
        )
        let randomButton = UIBarButtonItem(image: UIImage(systemName: "shuffle"), style: .plain, target: self, action: #selector(tapRandomButton))
        navigationItem.leftBarButtonItem = randomButton
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
