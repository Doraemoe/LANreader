import UIKit
import SwiftUI
import Combine
import ComposableArchitecture

class UIArchiveReaderController: UIViewController {
    private let store: StoreOf<ArchiveReaderFeature>
    private var hostingController: UIHostingController<ArchiveReader>!
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: StoreOf<ArchiveReaderFeature>,
        navigationHelper: NavigationHelper? = nil
    ) {
        self.store = store
        self.hostingController = UIHostingController(rootView: ArchiveReader(
            store: store, navigationHelper: navigationHelper
        ))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        if let currentArchive = store.allArchives[id: store.currentArchiveId] {
            navigationItem.title = currentArchive.wrappedValue.name
        }
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
            guard let currentArchive = store.allArchives[id: store.currentArchiveId] else { return }
            let detailsStore = Store(
                initialState: ArchiveDetailsFeature.State.init(archive: currentArchive, cached: store.cached)
            ) {
                ArchiveDetailsFeature()
            }

            navigationController?.pushViewController(
                UIHostingController(rootView: ArchiveDetailsV2(store: detailsStore, onDelete: {
                    if let viewControllers = self.navigationController?.viewControllers, viewControllers.count > 2 {
                        let destination = viewControllers[viewControllers.count - 3]
                        self.navigationController?.popToViewController(destination, animated: true)
                    }
                }, onTagNavigation: { store in
                    self.navigationController?
                        .pushViewController(UISearchViewV2Controller(store: store), animated: true)
                })),
                animated: true
            )
        }
        let detailsButton = UIBarButtonItem(primaryAction: detailsAction)

        navigationItem.rightBarButtonItem = detailsButton
    }

    private func setupObserve() {
        store.publisher.controlUiHidden
            .sink { [weak self] hidden in
                if hidden {
                    self?.navigationController?.setNavigationBarHidden(true, animated: false)
                } else {
                    self?.navigationController?.setNavigationBarHidden(false, animated: false)
                }
            }
            .store(in: &cancellables)
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
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
}
