import UIKit
import SwiftUI
import Combine
import ComposableArchitecture

class UIArchiveReaderController: UIViewController {
    private let store: StoreOf<ArchiveReaderFeature>
    private var hostingController: UIHostingController<ArchiveReader>!
    private var cancellables: Set<AnyCancellable> = []

    init(store: StoreOf<ArchiveReaderFeature>) {
        self.store = store
        self.hostingController = UIHostingController(rootView: ArchiveReader(store: store))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        navigationItem.title = store.archive.name
        navigationItem.largeTitleDisplayMode = .inline
        add(hostingController)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
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
        setupObserve()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
}
