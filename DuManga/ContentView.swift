//  Created 22/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer struct AppFeature {
    private let logger = Logger(label: "AppFeature")

    struct State: Equatable {
        var path = StackState<AppFeature.Path.State>()
        @PresentationState var destination: Destination.State?

        @BindingState var tabName = "library"
        var successMessage = ""
        var errorMessage = ""

        var library = LibraryFeature.State()
        var category = CategoryFeature.State()
        var search = SearchFeature.State()
        var settings = SettingsFeature.State()
    }

    enum Action: Equatable, BindableAction {
        case path(StackAction<AppFeature.Path.State, AppFeature.Path.Action>)
        case destination(PresentationAction<Destination.Action>)

        case binding(BindingAction<State>)

        case library(LibraryFeature.Action)
        case category(CategoryFeature.Action)
        case search(SearchFeature.Action)
        case settings(SettingsFeature.Action)

        case showLogin
        case showLockScreen
        case queueUrlDownload(URL)
        case setErrorMessage(String)
        case setSuccessMessage(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    var body: some Reducer<State, Action> {
        BindingReducer()

        Scope(state: \.library, action: \.library) {
            LibraryFeature()
        }
        Scope(state: \.category, action: \.category) {
            CategoryFeature()
        }
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .showLogin:
                state.destination = .login(LANraragiConfigFeature.State())
                return .none
            case .showLockScreen:
                state.destination = .lockScreen(
                    LockScreenFeature.State(lockState: .normal)
                )
                return .none
            case let .queueUrlDownload(url):
                return .run { send in
                    var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    comp.scheme = "https"
                    let urlToDownload = try comp.asURL().absoluteString
                    let response = try await service.queueUrlDownload(downloadUrl: urlToDownload).value
                    if response.success != 1 {
                        await send(.setErrorMessage(NSLocalizedString("error.download.queue", comment: "error")))
                    } else {
                        var downloadJob = DownloadJob(
                            id: response.job,
                            url: response.url,
                            title: "",
                            isActive: true,
                            isSuccess: false,
                            isError: false,
                            message: "",
                            lastUpdate: Date()
                        )
                        try database.saveDownloadJob(&downloadJob)
                        await send(.setSuccessMessage(NSLocalizedString("download.queue.success", comment: "success")))
                    }
                } catch: { error, send in
                    logger.error("failed to queue url to download. url=\(url) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .path(.element(id: id, action: .details(.deleteSuccess))):
                guard case .details = state.path[id: id]
                 else { return .none }
                let penultimateId = state.path.ids.dropLast().last
                state.path.pop(from: penultimateId!)
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                return .none
            case let .setSuccessMessage(message):
                state.successMessage = message
                return .none
            default:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            AppFeature.Path()
        }
        .ifLet(\.$destination, action: \.destination) {
            Destination()
        }
    }

    @Reducer struct Path {
        enum State: Equatable {
            case reader(ArchiveReaderFeature.State)
            case details(ArchiveDetailsFeature.State)
            case categoryArchiveList(CategoryArchiveListFeature.State)
            case search(SearchFeature.State)
        }
        enum Action: Equatable {
            case reader(ArchiveReaderFeature.Action)
            case details(ArchiveDetailsFeature.Action)
            case categoryArchiveList(CategoryArchiveListFeature.Action)
            case search(SearchFeature.Action)
        }
        var body: some ReducerOf<Self> {
            Scope(state: \.reader, action: \.reader) {
                ArchiveReaderFeature()
            }
            Scope(state: \.details, action: \.details) {
                ArchiveDetailsFeature()
            }
            Scope(state: \.categoryArchiveList, action: \.categoryArchiveList) {
                CategoryArchiveListFeature()
            }
            Scope(state: \.search, action: \.search) {
                SearchFeature()
            }
        }
    }

    @Reducer public struct Destination {
        public enum State: Equatable {
            case login(LANraragiConfigFeature.State)
            case lockScreen(LockScreenFeature.State)
        }

        public enum Action: Equatable {
            case login(LANraragiConfigFeature.Action)
            case lockScreen(LockScreenFeature.Action)
        }

        public var body: some Reducer<State, Action> {
            Scope(state: \.login, action: \.login) {
                LANraragiConfigFeature()
            }
            Scope(state: \.lockScreen, action: \.lockScreen) {
                LockScreenFeature()
            }
        }
    }
}

extension AppFeature {
    private static var _shared: StoreOf<AppFeature>?

    public static var shared: StoreOf<AppFeature> {
        if _shared == nil {
            _shared = Store(initialState: AppFeature.State(), reducer: {
                AppFeature()
            })
        }
        return _shared!
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""

    let store: StoreOf<AppFeature>

    private let noAnimationTransaction: Transaction

    init(store: StoreOf<AppFeature>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        self.noAnimationTransaction = transaction

        self.store = store
    }

    struct ViewState: Equatable {
        @BindingViewState var tabName: String
        let destination: AppFeature.Destination.State?
        let successMessage: String
        let errorMessage: String
        init(bindingViewStore: BindingViewStore<AppFeature.State>) {
            self._tabName = bindingViewStore.$tabName
            self.destination = bindingViewStore.destination
            self.successMessage = bindingViewStore.successMessage
            self.errorMessage = bindingViewStore.errorMessage
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            TabView(selection: viewStore.$tabName) {
                libraryView
                categoryView
                searchView
                settingsView
            }
            .fullScreenCover(
                store: self.store.scope(state: \.$destination, action: { .destination($0) }),
                state: \.login,
                action: { .login($0) }
            ) { store in
                LANraragiConfigView(store: store)
            }
            .fullScreenCover(
                store: self.store.scope(state: \.$destination, action: { .destination($0) }),
                state: \.lockScreen,
                action: { .lockScreen($0) }
            ) { store in
                LockScreen(store: store)
            }
            .onAppear {
                if UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl)?.isEmpty != false {
                    viewStore.send(.showLogin)
                }
            }
            .onAppear {
                if !storedPasscode.isEmpty {
                    _ = withTransaction(self.noAnimationTransaction) {
                        viewStore.send(.showLockScreen)
                    }
                }
            }
            .onChange(of: scenePhase) {
                if !storedPasscode.isEmpty && scenePhase != .active && viewStore.destination == nil {
                    _ = withTransaction(self.noAnimationTransaction) {
                        viewStore.send(.showLockScreen)
                    }
                }
            }
            .onOpenURL { url in
                viewStore.send(.queueUrlDownload(url))
            }
            .onChange(of: viewStore.errorMessage) {
                if !viewStore.errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("error", comment: "error"),
                        subtitle: viewStore.errorMessage,
                        style: .danger
                    )
                    banner.show()
                    viewStore.send(.setErrorMessage(""))
                }
            }
            .onChange(of: viewStore.successMessage) {
                if !viewStore.successMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("success", comment: "success"),
                        subtitle: viewStore.successMessage,
                        style: .success
                    )
                    banner.show()
                    viewStore.send(.setSuccessMessage(""))
                }
            }
        }
    }

    var libraryView: some View {
        NavigationStackStore(
            self.store.scope(state: \.path, action: { .path($0) })
        ) {
            LibraryListV2(store: store.scope(state: \.library, action: {
                .library($0)
            }))
        } destination: { (state: AppFeature.Path.State) in
            switch state {
            case .reader:
                CaseLet(
                    /AppFeature.Path.State.reader,
                     action: AppFeature.Path.Action.reader,
                     then: ArchiveReader.init(store:)
                )
            case .details:
                CaseLet(
                    /AppFeature.Path.State.details,
                     action: AppFeature.Path.Action.details,
                     then: ArchiveDetailsV2.init(store:)
                )
            case .categoryArchiveList:
                CaseLet(
                    /AppFeature.Path.State.categoryArchiveList,
                     action: AppFeature.Path.Action.categoryArchiveList,
                     then: CategoryArchiveListV2.init(store:)
                )
            case .search:
                CaseLet(
                    /AppFeature.Path.State.search,
                     action: AppFeature.Path.Action.search,
                     then: SearchViewV2.init(store:)
                )
            }
        }
        .tabItem {
            Image(systemName: "books.vertical")
            Text("library")
        }
        .tag("library")
    }

    var categoryView: some View {
        NavigationStackStore(
            self.store.scope(state: \.path, action: { .path($0) })
        ) {
            CategoryListV2(store: store.scope(state: \.category, action: {
                .category($0)
            }))
        } destination: { (state: AppFeature.Path.State) in
            switch state {
            case .reader:
                CaseLet(
                    /AppFeature.Path.State.reader,
                     action: AppFeature.Path.Action.reader,
                     then: ArchiveReader.init(store:)
                )
            case .details:
                CaseLet(
                    /AppFeature.Path.State.details,
                     action: AppFeature.Path.Action.details,
                     then: ArchiveDetailsV2.init(store:)
                )
            case .categoryArchiveList:
                CaseLet(
                    /AppFeature.Path.State.categoryArchiveList,
                     action: AppFeature.Path.Action.categoryArchiveList,
                     then: CategoryArchiveListV2.init(store:)
                )
            case .search:
                CaseLet(
                    /AppFeature.Path.State.search,
                     action: AppFeature.Path.Action.search,
                     then: SearchViewV2.init(store:)
                )
            }
        }
        .tabItem {
            Image(systemName: "folder")
            Text("category")
        }
        .tag("category")
    }

    var searchView: some View {
        NavigationStackStore(
            self.store.scope(state: \.path, action: { .path($0) })
        ) {
            SearchViewV2(store: store.scope(state: \.search, action: {
                .search($0)
            }))
        } destination: { (state: AppFeature.Path.State) in
            switch state {
            case .reader:
                CaseLet(
                    /AppFeature.Path.State.reader,
                     action: AppFeature.Path.Action.reader,
                     then: ArchiveReader.init(store:)
                )
            case .details:
                CaseLet(
                    /AppFeature.Path.State.details,
                     action: AppFeature.Path.Action.details,
                     then: ArchiveDetailsV2.init(store:)
                )
            case .categoryArchiveList:
                CaseLet(
                    /AppFeature.Path.State.categoryArchiveList,
                     action: AppFeature.Path.Action.categoryArchiveList,
                     then: CategoryArchiveListV2.init(store:)
                )
            case .search:
                CaseLet(
                    /AppFeature.Path.State.search,
                     action: AppFeature.Path.Action.search,
                     then: SearchViewV2.init(store:)
                )
            }
        }
        .tabItem {
            Image(systemName: "magnifyingglass")
            Text("search")
        }
        .tag("search")
    }

    var settingsView: some View {
        SettingsView(store: store.scope(state: \.settings, action: {
            .settings($0)
        }))
        .tabItem {
            Image(systemName: "gearshape")
            Text("settings")
        }
        .tag("settings")
    }
}
