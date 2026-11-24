// Created 29/8/20
import ComposableArchitecture
import SwiftUI

@Reducer public struct SettingsFeature {
    @Reducer
    public enum Path {
        case serverConfig(LANraragiConfigFeature)
        case upload(UploadFeature)
        case translation(TranslationConfigFeature)
        case support(SupportFeature)
        case log(LogFeature)
    }

    @ObservableState
    public struct State: Equatable {
        var path = StackState<Path.State>()
        var read = ReadSettingsFeature.State()
        var view = ViewSettingsFeature.State()
        var database = DatabaseSettingsFeature.State()
    }
    public enum Action {
        case path(StackActionOf<Path>)
        case read(ReadSettingsFeature.Action)
        case view(ViewSettingsFeature.Action)
        case database(DatabaseSettingsFeature.Action)

        case serverConfigTapped
        case uploadTapped
        case translationTapped
        case supportTapped
        case logTapped
    }

    public var body: some ReducerOf<Self> {
        Scope(\.read, action: \.read) {
            ReadSettingsFeature()
        }

        Scope(\.view, action: \.view) {
            ViewSettingsFeature()
        }

        Scope(\.database, action: \.database) {
            DatabaseSettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .serverConfigTapped:
                state.path.append(.serverConfig(LANraragiConfigFeature.State()))
                return .none
            case .uploadTapped:
                state.path.append(.upload(UploadFeature.State()))
                return .none
            case .translationTapped:
                state.path.append(.translation(TranslationConfigFeature.State()))
                return .none
            case .supportTapped:
                state.path.append(.support(SupportFeature.State()))
                return .none
            case .logTapped:
                state.path.append(.log(LogFeature.State()))
                return .none
            case .path, .read, .view, .database:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            Path.body.synchronousCancellation()
        }
    }
}

extension SettingsFeature.Path.State: Equatable {}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Form {
            Section(
                header: Text("settings.read")
            ) {
                ReadSettings(store: self.store.scope(\.read, action: \.read))
            }
            Section(header: Text("settings.host")) {
                ServerSettings(
                    onConfigTap: { store.send(.serverConfigTapped) },
                    onUploadTap: { store.send(.uploadTapped) }
                )
            }
            Section(header: Text("settings.view")) {
                ViewSettings(store: self.store.scope(\.view, action: \.view))
            }
            Section(
                header: Text("settings.advanced"),
            ) {
                AdvancedSettings(
                    onTranslationTap: { store.send(.translationTapped) }
                )
            }
            Section(header: Text("settings.database")) {
                DatabaseSettings(store: self.store.scope(\.database, action: \.database))
            }
            Section(header: Text("settings.support")) {
                SupportSettings(
                    onSupportTap: { store.send(.supportTapped) },
                    onLogTap: { store.send(.logTapped) }
                )
            }
        }
    }
}

class UISettingsViewController: UIViewController {
    private let store: StoreOf<SettingsFeature>

    init(store: StoreOf<SettingsFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: SettingsView(store: store)
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
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(false, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = false
        }
    }
}

@MainActor
func makeSettingsNavigationController(store: StoreOf<SettingsFeature>) -> NavigationStackController {
    @UIBindable var store = store
    return NavigationStackController(
        path: $store.scope(\.path, action: \.path),
        root: {
            let settingsView = UISettingsViewController(store: store)
            settingsView.navigationItem.title = String(localized: "settings")
            return settingsView
        },
        destination: { store in
            switch store.case {
            case let .serverConfig(store):
                UILANraragiConfigViewController(store: store)
            case let .upload(store):
                UIUploadViewController(store: store)
            case let .translation(store):
                UITranslationConfigController(store: store)
            case let .support(store):
                UISupportViewController(store: store)
            case let .log(store):
                UILogViewController(store: store)
            }
        }
    )
}
