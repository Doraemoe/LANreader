//  Created 23/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer public struct LANraragiConfigFeature {
    private let logger = Logger(label: "LANraragiConfigFeature")

    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SettingsKey.serverProgress)) var serverProgress = false
        @Shared(.appStorage(SettingsKey.lanraragiUrl)) var url = ""
        @Shared(.appStorage(SettingsKey.lanraragiApiKey)) var apiKey = ""

        var formUrl = ""
        var formKey = ""

        var isVerifying = false
        var successVerifed = false
        var errorMessage = ""
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case verifyServer
        case saveComplate
        case setErrorMessage(String)

        case setFormValue
        case setServerProgress(Bool)
        case setLanraragiUrl(String)
        case setLanraragiApiKey(String)
    }

    @Dependency(\.lanraragiService) var lanraragiService
    @Dependency(\.isPresented) var isPresented
    @Dependency(\.dismiss) var dismiss

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .verifyServer:
                state.isVerifying = true
                return .run { [state] send in
                    let serverInfo = try await lanraragiService.verifyClient(
                        url: state.formUrl, apiKey: state.formKey
                    ).value
                    if serverInfo.serverTracksProgress {
                        await send(.setServerProgress(true))
                    } else {
                        await send(.setServerProgress(false))
                    }
                    await send(.setLanraragiApiKey(state.formKey))
                    await send(.setLanraragiUrl(state.formUrl))
                    await send(.saveComplate)
                } catch: { error, send in
                    logger.error("failed to verify lanraragi server. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case .saveComplate:
                state.isVerifying = false
                state.successVerifed = true
                return .run { _ in
                    if isPresented {
                        await self.dismiss()
                    }
                }
            case let .setErrorMessage(errorMessage):
                state.errorMessage = errorMessage
                state.isVerifying = false
                return .none
            case .binding:
                return .none
            case .setFormValue:
                state.formUrl = state.url
                state.formKey = state.apiKey
                return .none
            case let .setServerProgress(isServerProgress):
                state.$serverProgress.withLock {
                    $0 = isServerProgress
                }
                return .none
            case let .setLanraragiUrl(url):
                state.$url.withLock {
                    $0 = url
                }
                return .none
            case let .setLanraragiApiKey(key):
                state.$apiKey.withLock {
                    $0 = key
                }
                return .none
            }
        }
    }
}

struct LANraragiConfigView: View {

    enum FocusedField {
        case url, apiKey
    }

    @FocusState private var focused: FocusedField?

    @Bindable var store: StoreOf<LANraragiConfigFeature>

    var navigation: NavigationHelper?

    var body: some View {
        Form {
            Section(footer: Text("lanraragi.config.url.explain")) {
                TextField("lanraragi.config.url", text: $store.formUrl)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused, equals: .url)
                SecureField("lanraragi.config.apiKey", text: $store.formKey)
                    .focused($focused, equals: .apiKey)
            }
            Section {
                Button(action: {
                    store.send(.verifyServer)
                }, label: {
                    Text("lanraragi.config.submit")
                        .font(.headline)
                })
                .disabled(store.isVerifying)
            }
        }
        .onAppear {
            store.send(.setFormValue)
        }
        .onSubmit {
            if focused == .url {
                focused = .apiKey
            } else {
                store.send(.verifyServer)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                banner.show()
                store.send(.setErrorMessage(""))
            }
        }
        .onChange(of: store.successVerifed) { _, newValue in
            if newValue == true {
                navigation?.pop()
            }
        }
    }
}

class UILANraragiConfigViewController: UIViewController {
    private let store: StoreOf<LANraragiConfigFeature>
    private let navigation: NavigationHelper

    init(store: StoreOf<LANraragiConfigFeature>, navigation: NavigationHelper) {
        self.store = store
        self.navigation = navigation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: LANraragiConfigView(store: store, navigation: navigation)
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
            tabBarController?.setTabBarHidden(true, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = true
        }
    }
}
