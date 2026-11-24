//  Created 23/8/20.
import Alamofire
import ComposableArchitecture
import SwiftUI
import Logging

@Reducer public struct LANraragiConfigFeature: Sendable {
    private let logger = Logger(label: "LANraragiConfigFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        @Shared(.appStorage(SettingsKey.serverProgress)) var serverProgress = false
        @Shared(.appStorage(SettingsKey.lanraragiUrl)) var url = ""
        @Shared(.appStorage(SettingsKey.lanraragiApiKey)) var apiKey = ""

        @Presents var alert: AlertState<Action.Alert>?

        var formUrl = ""
        var formKey = ""

        var isVerifying = false
        var errorMessage = ""

        public init() {
            self.formUrl = self.url
            self.formKey = self.apiKey
        }
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case verifyServer
        case saveComplate
        case setErrorMessage(String)
        case showInsecureConnectionAlert
        case alert(PresentationAction<Alert>)

        case setServerProgress(Bool)
        case setLanraragiUrl(String)
        case setLanraragiApiKey(String)

        public enum Alert: Equatable, Sendable {}
    }

    @Dependency(\.lanraragiService) var lanraragiService
    @Dependency(\.dismiss) var dismiss

    // App Transport Security rejects plain HTTP to anything it does not consider local, which
    // includes the 100.64.0.0/10 range Tailscale assigns. Alamofire wraps the URL error once.
    static func isInsecureConnectionFailure(_ error: Error) -> Bool {
        let underlying = (error.asAFError?.underlyingError ?? error) as NSError
        return underlying.domain == NSURLErrorDomain
            && underlying.code == NSURLErrorAppTransportSecurityRequiresSecureConnection
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .verifyServer:
                state.isVerifying = true
                return .run { [state] send in
                    let serverInfo = try await lanraragiService.verifyClient(
                        url: state.formUrl, apiKey: state.formKey
                    )
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
                    if Self.isInsecureConnectionFailure(error) {
                        await send(.showInsecureConnectionAlert)
                    } else {
                        await send(.setErrorMessage(error.localizedDescription))
                    }
                }
            case .showInsecureConnectionAlert:
                state.isVerifying = false
                state.alert = AlertState {
                    TextState("lanraragi.config.error.insecure.title")
                } message: {
                    TextState("lanraragi.config.error.insecure.message")
                }
                return .none
            case .alert:
                return .none
            case .saveComplate:
                state.isVerifying = false
                return .run { _ in
                    await self.dismiss()
                }
            case let .setErrorMessage(errorMessage):
                state.errorMessage = errorMessage
                state.isVerifying = false
                return .none
            case .binding:
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
        .ifLet(\.$alert, action: \.alert)
    }
}

struct LANraragiConfigView: View {

    enum FocusedField {
        case url, apiKey
    }

    @FocusState private var focused: FocusedField?

    @Bindable var store: StoreOf<LANraragiConfigFeature>

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
        .onSubmit {
            if focused == .url {
                focused = .apiKey
            } else {
                store.send(.verifyServer)
            }
        }
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                showNotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                store.send(.setErrorMessage(""))
            }
        }
        .alert($store.scope(\.$alert, action: \.alert))
    }
}
