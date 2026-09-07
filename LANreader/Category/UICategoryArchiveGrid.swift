import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer public struct CategoryArchiveListFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared(.inMemory(SettingsKey.tabBarHidden)) var tabBarHidden = false

        var id: String
        var name: String

        var archiveList: ArchiveListFeature.State
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case archiveList(ArchiveListFeature.Action)
    }

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(\.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

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
        navigationItem.largeTitleDisplayMode = .never

        let archiveListView = UIArchiveListViewController(
            store: store.scope(\.archiveList, action: \.archiveList)
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
