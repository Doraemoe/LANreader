import UIKit
import SwiftUI
import ComposableArchitecture

class UIArchiveReaderController: UIViewController {
    private let store: StoreOf<ArchiveReaderFeature>
    private var hostingController: UIHostingController<ArchiveReader>!
    private var detailsButton: UIBarButtonItem?

    override var prefersStatusBarHidden: Bool {
        store.controlUiHidden
    }

    init(store: StoreOf<ArchiveReaderFeature>) {
        self.store = store
        self.hostingController = UIHostingController(rootView: ArchiveReader(store: store))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        navigationItem.largeTitleDisplayMode = .inline
        add(hostingController)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func setupToolbar() {
        let detailsAction = UIAction(image: UIImage(systemName: "info.circle")) { [weak self] _ in
            guard let self else { return }
            guard store.canOpenDetails else { return }
            store.send(.openDetailsTapped)
        }
        let detailsButton = UIBarButtonItem(primaryAction: detailsAction)
        detailsButton.isEnabled = store.canOpenDetails
        self.detailsButton = detailsButton

        navigationItem.rightBarButtonItem = detailsButton
    }

    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            let controlUiHidden = store.controlUiHidden
            guard self.navigationController?.topViewController === self else { return }
            self.navigationController?.setNavigationBarHidden(controlUiHidden, animated: false)
            self.setNeedsStatusBarAppearanceUpdate()
        }

        observe { [weak self] in
            guard let self else { return }
            guard let currentArchive = store.allArchives[id: store.currentArchiveId] else { return }
            navigationItem.title = currentArchive.wrappedValue.name
        }

        observe { [weak self] in
            guard let self else { return }
            detailsButton?.isEnabled = store.canOpenDetails
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupToolbar()
        setupObserve()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(store.controlUiHidden, animated: animated)
        updateTabBarVisibility()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTabBarVisibility()
    }

    private func updateTabBarVisibility() {
        if #available(iOS 18.0, *) {
            if tabBarController?.isTabBarHidden == false {
                tabBarController?.setTabBarHidden(true, animated: false)
            }
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }
}
