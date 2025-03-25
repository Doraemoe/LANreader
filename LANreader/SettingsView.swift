// Created 29/8/20
import ComposableArchitecture
import SwiftUI

@Reducer public struct SettingsFeature {
    @ObservableState
    public struct State: Equatable {
        var path = StackState<Path.State>()

        var read = ReadSettingsFeature.State()
        var view = ViewSettingsFeature.State()
        var database = DatabaseSettingsFeature.State()
    }
    public enum Action {
        case path(StackAction<Path.State, Path.Action>)

        case read(ReadSettingsFeature.Action)
        case view(ViewSettingsFeature.Action)
        case database(DatabaseSettingsFeature.Action)
    }

    public var body: some ReducerOf<Self> {
        Scope(state: \.read, action: \.read) {
            ReadSettingsFeature()
        }

        Scope(state: \.view, action: \.view) {
            ViewSettingsFeature()
        }

        Scope(state: \.database, action: \.database) {
            DatabaseSettingsFeature()
        }

        Reduce { _, action in
            switch action {
            default:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }

    @Reducer(state: .equatable)
    public enum Path {
        case lanraragiSettings(LANraragiConfigFeature)
        case upload(UploadFeature)
        case log(LogFeature)
    }
}

struct SettingsView: View {
    @Environment(NavigationHelper.self) private var navigation

    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Form {
            Section(
                header: Text("settings.read")
            ) {
                ReadSettings(store: self.store.scope(state: \.read, action: \.read))
            }
            Section(header: Text("settings.host")) {
                ServerSettings()
            }
            Section(
                header: Text("settings.view"),
                footer: Text("settings.archive.list.order.custom.explain")
            ) {
                ViewSettings(store: self.store.scope(state: \.view, action: \.view))
            }
            Section(header: Text("settings.database")) {
                DatabaseSettings(store: self.store.scope(state: \.database, action: \.database))
            }
            Section(header: Text("settings.debug")) {
                Button {
                    let store = Store(initialState: LogFeature.State()) {
                        LogFeature()
                    }
                    navigation.push(UILogViewController(store: store))
                } label: {
                    HStack {
                        Text("settings.debug.log")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.primary)
                .padding()
                // swiftlint:disable force_cast
                let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
                let build = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
                // swiftlint:enable force_cast
                LabeledContent("version", value: "\(version)-\(build)")
                    .padding()
            }
            Section(header: Text("settings.support")) {
                SupportSettings()
            }
        }
    }
}

class UISettingsViewController: UIViewController {
    private let store: StoreOf<SettingsFeature>
    private let navigationHelper: NavigationHelper

    init(store: StoreOf<SettingsFeature>, navigationHelper: NavigationHelper) {
        self.store = store
        self.navigationHelper = navigationHelper
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: SettingsView(store: store)
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
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(false, animated: false)
        }
    }
}
