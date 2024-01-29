//  Created 22/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer struct AppFeature {
    private let logger = Logger(label: "AppFeature")

    @ObservableState
    struct State: Equatable {
        var path = StackState<AppFeature.Path.State>()
        @Presents var destination: Destination.State?

        var tabName = "library"
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
                        await send(.setErrorMessage(String(localized: "error.download.queue")))
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
                        await send(.setSuccessMessage(String(localized: "download.queue.success")))
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
        @ObservableState
        enum State: Equatable {
            case reader(ArchiveReaderFeature.State)
            case details(ArchiveDetailsFeature.State)
            case categoryArchiveList(CategoryArchiveListFeature.State)
            case search(SearchFeature.State)
            case random(RandomFeature.State)
        }
        enum Action: Equatable {
            case reader(ArchiveReaderFeature.Action)
            case details(ArchiveDetailsFeature.Action)
            case categoryArchiveList(CategoryArchiveListFeature.Action)
            case search(SearchFeature.Action)
            case random(RandomFeature.Action)
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
            Scope(state: \.random, action: \.random) {
                RandomFeature()
            }
        }
    }

    @Reducer public struct Destination {
        @ObservableState
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

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""

    @Bindable var store: StoreOf<AppFeature>

    private let noAnimationTransaction: Transaction

    init(store: StoreOf<AppFeature>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        self.noAnimationTransaction = transaction

        self.store = store
    }

    var body: some View {
        TabView(selection: $store.tabName) {
            libraryView
            categoryView
            searchView
            settingsView
        }
        .fullScreenCover(
            item: $store.scope(state: \.destination?.login, action: \.destination.login)
        ) { store in
            LANraragiConfigView(store: store)
        }
        .fullScreenCover(
            item: $store.scope(state: \.destination?.lockScreen, action: \.destination.lockScreen)
        ) { store in
            LockScreen(store: store)
        }
        .onAppear {
            if UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl)?.isEmpty != false {
                store.send(.showLogin)
            }
        }
        .onAppear {
            if !storedPasscode.isEmpty {
                _ = withTransaction(self.noAnimationTransaction) {
                    store.send(.showLockScreen)
                }
            }
        }
        .onChange(of: scenePhase) {
            if !storedPasscode.isEmpty && scenePhase != .active && store.destination == nil {
                _ = withTransaction(self.noAnimationTransaction) {
                    store.send(.showLockScreen)
                }
            }
        }
        .onOpenURL { url in
            store.send(.queueUrlDownload(url))
        }
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
        .onChange(of: store.successMessage) {
            if !store.successMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "success"),
                    subtitle: store.successMessage,
                    style: .success
                )
                banner.show()
                store.send(.setSuccessMessage(""))
            }
        }
    }

    var libraryView: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            LibraryListV2(store: store.scope(state: \.library, action: \.library))
        } destination: { store in
            switch store.state {
            case .reader:
                if let store = store.scope(state: \.reader, action: \.reader) {
                    ArchiveReader(store: store)
                }
            case .details:
                if let store = store.scope(state: \.details, action: \.details) {
                    ArchiveDetailsV2(store: store)
                }
            case .categoryArchiveList:
                if let store = store.scope(state: \.categoryArchiveList, action: \.categoryArchiveList) {
                    CategoryArchiveListV2(store: store)
                }
            case .search:
                if let store = store.scope(state: \.search, action: \.search) {
                    SearchViewV2(store: store)
                }
            case .random:
                if let store = store.scope(state: \.random, action: \.random) {
                    RandomView(store: store)
                }
            }
        }
        .tabItem {
            Image(systemName: "books.vertical")
            Text("library")
        }
        .tag("library")
    }

    var categoryView: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            CategoryListV2(store: store.scope(state: \.category, action: \.category))
        } destination: { store in
            switch store.state {
            case .reader:
                if let store = store.scope(state: \.reader, action: \.reader) {
                    ArchiveReader(store: store)
                }
            case .details:
                if let store = store.scope(state: \.details, action: \.details) {
                    ArchiveDetailsV2(store: store)
                }
            case .categoryArchiveList:
                if let store = store.scope(state: \.categoryArchiveList, action: \.categoryArchiveList) {
                    CategoryArchiveListV2(store: store)
                }
            case .search:
                if let store = store.scope(state: \.search, action: \.search) {
                    SearchViewV2(store: store)
                }
            case .random:
                if let store = store.scope(state: \.random, action: \.random) {
                    RandomView(store: store)
                }
            }
        }
        .tabItem {
            Image(systemName: "folder")
            Text("category")
        }
        .tag("category")
    }

    var searchView: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            SearchViewV2(store: store.scope(state: \.search, action: \.search))
        } destination: { store in
            switch store.state {
            case .reader:
                if let store = store.scope(state: \.reader, action: \.reader) {
                    ArchiveReader(store: store)
                }
            case .details:
                if let store = store.scope(state: \.details, action: \.details) {
                    ArchiveDetailsV2(store: store)
                }
            case .categoryArchiveList:
                if let store = store.scope(state: \.categoryArchiveList, action: \.categoryArchiveList) {
                    CategoryArchiveListV2(store: store)
                }
            case .search:
                if let store = store.scope(state: \.search, action: \.search) {
                    SearchViewV2(store: store)
                }
            case .random:
                if let store = store.scope(state: \.random, action: \.random) {
                    RandomView(store: store)
                }
            }
        }
        .tabItem {
            Image(systemName: "magnifyingglass")
            Text("search")
        }
        .tag("search")
    }

    var settingsView: some View {
        SettingsView(store: store.scope(state: \.settings, action: \.settings))
            .tabItem {
                Image(systemName: "gearshape")
                Text("settings")
            }
            .tag("settings")
    }
}
