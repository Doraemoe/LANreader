//  Created 22/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer public struct AppFeature {
    private let logger = Logger(label: "AppFeature")

    @ObservableState
    public struct State: Equatable {
        var path = StackState<AppFeature.Path.State>()
        @Presents var destination: Destination.State?

        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @SharedReader(.appStorage(SettingsKey.passcode)) var storedPasscode = ""
        @SharedReader(.appStorage(SettingsKey.blurInterfaceWhenInactive)) var blurInterfaceWhenInactive = false

        var tabName = "library"
        var successMessage = ""
        var errorMessage = ""

        var library = LibraryFeature.State()
        var category = CategoryFeature.State()
        var search = SearchFeature.State()
        var settings = SettingsFeature.State()
    }

    public enum Action: BindableAction {
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

    public var body: some Reducer<State, Action> {
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
        .forEach(\.path, action: \.path)
        .ifLet(\.$destination, action: \.destination)
    }

    @Reducer(state: .equatable)
    public enum Path {
        case reader(ArchiveReaderFeature)
        case details(ArchiveDetailsFeature)
        case categoryArchiveList(CategoryArchiveListFeature)
        case search(SearchFeature)
        case random(RandomFeature)
        case cache(CacheFeature)
    }

    @Reducer(state: .equatable)
    public enum Destination {
        case login(LANraragiConfigFeature)
        case lockScreen(LockScreenFeature)
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase

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
        .modifier(Covers(store: store))
        .onAppear {
            if store.lanraragiUrl.isEmpty != false {
                store.send(.showLogin)
            }
        }
        .onAppear {
            if !store.storedPasscode.isEmpty {
                _ = withTransaction(self.noAnimationTransaction) {
                    store.send(.showLockScreen)
                }
            }
        }
        .onChange(of: scenePhase) {
            if !store.storedPasscode.isEmpty && scenePhase != .active && store.destination == nil {
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
//        NavigationStack(
//            path: $store.scope(state: \.path, action: \.path)
//        ) {
//            UILibraryList(store: store.scope(state: \.library, action: \.library))
//        } destination: { store in
//            switch store.case {
//            case let .reader(store):
//                ArchiveReader(store: store)
//            case let .details(store):
//                ArchiveDetailsV2(store: store)
//            case let .categoryArchiveList(store):
//                CategoryArchiveListV2(store: store)
//            case let .search(store):
//                SearchViewV2(store: store)
//            case let .random(store):
//                RandomView(store: store)
//            case let .cache(store):
//                CacheView(store: store)
//            }
//        }
        UILibraryList(store: store)
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
            switch store.case {
            case let .reader(store):
                ArchiveReader(store: store)
            case let .details(store):
                ArchiveDetailsV2(store: store)
            case let .categoryArchiveList(store):
                CategoryArchiveListV2(store: store)
            case let .search(store):
                SearchViewV2(store: store)
            case let .random(store):
                RandomView(store: store)
            case let .cache(store):
                CacheView(store: store)
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
            switch store.case {
            case let .reader(store):
                ArchiveReader(store: store)
            case let .details(store):
                ArchiveDetailsV2(store: store)
            case let .categoryArchiveList(store):
                CategoryArchiveListV2(store: store)
            case let .search(store):
                SearchViewV2(store: store)
            case let .random(store):
                RandomView(store: store)
            case let .cache(store):
                CacheView(store: store)
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

// Stupid SwiftUI will complain 'The compiler is unable to type-check this expression in reasonable time' otherwise
struct Covers: ViewModifier {
    @Bindable var store: StoreOf<AppFeature>

    func body(content: Content) -> some View {
        content
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
    }
}

@nonobjc extension UIViewController {
    func add(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }

    func remove() {
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }
}
