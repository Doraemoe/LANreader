import ComposableArchitecture
import SwiftUI
import UIKit

public struct UILibraryList: UIViewControllerRepresentable {
    let store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        LibraryNavigationController(store: store)
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
    }
}

class LibraryNavigationController: NavigationStackController {
    private var store: StoreOf<AppFeature>!

    convenience init(store: StoreOf<AppFeature>) {
        @UIBindable var store = store

        self.init(path: $store.scope(state: \.path, action: \.path)) {
            UILibraryListViewController(store: store.scope(state: \.library, action: \.library))
        } destination: { store in
            switch store.case {
            case let .reader(store):
                UIHostingController(rootView: ArchiveReader(store: store))
            case let .details(store):
                UIHostingController(rootView: ArchiveDetailsV2(store: store))
            case let .categoryArchiveList(store):
                UIHostingController(rootView: CategoryArchiveListV2(store: store))
            case let .search(store):
                UIHostingController(rootView: SearchViewV2(store: store))
            case let .random(store):
                UIHostingController(rootView: RandomView(store: store))
            case let .cache(store):
                UIHostingController(rootView: CacheView(store: store))
            }
        }
        self.store = store
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
        add(archiveListView)
        NSLayoutConstraint.activate([
            archiveListView.view.topAnchor.constraint(equalTo: view.topAnchor),
            archiveListView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            archiveListView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            archiveListView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
