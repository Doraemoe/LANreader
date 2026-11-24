//  Created 22/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@MainActor
func showNotificationBanner(title: String, subtitle: String, style: BannerStyle) {
    let banner = FloatingNotificationBanner(title: title, subtitle: subtitle, style: style)
    let safeAreaInsets = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)?
        .safeAreaInsets ?? .zero

    banner.show(
        edgeInsets: notificationBannerEdgeInsets(safeAreaInsets: safeAreaInsets),
        cornerRadius: 14
    )
}

func notificationBannerEdgeInsets(safeAreaInsets: UIEdgeInsets) -> UIEdgeInsets {
    UIEdgeInsets(
        top: safeAreaInsets.top + 8,
        left: safeAreaInsets.left + 8,
        bottom: 8,
        right: safeAreaInsets.right + 8
    )
}

@Reducer public struct AppFeature: Sendable {
    private let logger = Logger(label: "AppFeature")

    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?
        var selectedTab: TabName = .library

        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @SharedReader(.appStorage(SettingsKey.passcode)) var storedPasscode = ""
        @SharedReader(.appStorage(SettingsKey.blurInterfaceWhenInactive)) var blurInterfaceWhenInactive = false

        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []

        var pendingDeepLink: DeepLinkRoute?
        var successMessage = ""
        var errorMessage = ""

        var library = LibraryFeature.State()
        var category = CategoryFeature.State()
        var search = SearchTabFeature.State()
        var settings = SettingsFeature.State()

        public init(
            selectedTab: TabName = .library,
            destination: Destination.State? = nil
        ) {
            self.selectedTab = selectedTab
            if let destination {
                self.destination = destination
            } else if !self.storedPasscode.isEmpty {
                self.destination = .lockScreen(LockScreenFeature.State(lockState: .normal))
            } else if self.lanraragiUrl.isEmpty {
                self.destination = .login(LANraragiConfigFeature.State())
            }
        }
    }

    public enum Action: BindableAction {
        case destination(PresentationAction<Destination.Action>)

        case binding(BindingAction<State>)

        case library(LibraryFeature.Action)
        case category(CategoryFeature.Action)
        case search(SearchTabFeature.Action)
        case settings(SettingsFeature.Action)

        case selectTab(TabName)
        case showLockScreen
        case openURL(URL)
        case deepLinkArchiveLoaded(ArchiveItem, cached: Bool)
        case queueUrlDownload(URL)
        case setErrorMessage(String)
        case setSuccessMessage(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Scope(\.library, action: \.library) {
            LibraryFeature()
        }
        Scope(\.category, action: \.category) {
            CategoryFeature()
        }
        Scope(\.search, action: \.search) {
            SearchTabFeature()
        }
        Scope(\.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case let .selectTab(tab):
                state.selectedTab = tab
                return .none
            case .showLockScreen:
                state.destination = .lockScreen(
                    LockScreenFeature.State(lockState: .normal)
                )
                return .none
            case .destination(.dismiss):
                guard let route = state.pendingDeepLink else {
                    return .none
                }
                return openDeepLink(route, state: &state)
            case let .openURL(url):
                switch DeepLink(url: url) {
                case let .read(archiveId, preferCached):
                    return loadDeepLinkArchive(id: archiveId, preferCached: preferCached)
                case let .search(query):
                    return openOrQueueDeepLink(.search(query: query), state: &state)
                case let .download(downloadURL):
                    return .send(.queueUrlDownload(downloadURL))
                case nil:
                    logger.warning("ignored unsupported link. url=\(url)")
                    return .none
                }
            case let .deepLinkArchiveLoaded(archive, cached):
                if !cached {
                    state.$archiveItems.withLock { _ = $0.updateOrAppend(archive) }
                }
                return openOrQueueDeepLink(.reader(archive, cached: cached), state: &state)
            case let .queueUrlDownload(url):
                return .run { send in
                    let response = try await service.queueUrlDownload(downloadUrl: url.absoluteString).value
                    guard var downloadJob = response.toQueuedDownloadJob(lastUpdate: Date()) else {
                        await send(.setErrorMessage(String(localized: "error.download.queue")))
                        return
                    }
                    try database.saveDownloadJob(&downloadJob)
                    await send(.setSuccessMessage(String(localized: "download.queue.success")))
                } catch: { error, send in
                    logger.error("failed to queue url to download. url=\(url) \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
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
        .ifLet(\.$destination, action: \.destination)
    }

    private func openOrQueueDeepLink(
        _ route: DeepLinkRoute,
        state: inout State
    ) -> Effect<Action> {
        guard state.destination == nil else {
            state.pendingDeepLink = route
            return .none
        }
        return openDeepLink(route, state: &state)
    }

    private func openDeepLink(
        _ route: DeepLinkRoute,
        state: inout State
    ) -> Effect<Action> {
        state.pendingDeepLink = nil
        switch route {
        case let .reader(archive, cached):
            state.selectedTab = .library
            return .send(.library(.openDeepLinkReader(archive, cached: cached)))
        case let .search(query):
            state.selectedTab = .search
            return .send(.search(.openDeepLinkSearch(query)))
        }
    }

    private func loadDeepLinkArchive(id: String, preferCached: Bool) -> Effect<Action> {
        .run { send in
            if preferCached, let cache = try? database.readCache(id), cache.cached {
                await send(.deepLinkArchiveLoaded(cache.toArchiveItem(), cached: true))
                return
            }
            do {
                let archive = if id.isTankoubonArchiveId {
                    try await tankoubonArchiveItem(id: id)
                } else {
                    try await service.retrieveArchiveMetadata(id: id).value.toArchiveItem()
                }
                await send(.deepLinkArchiveLoaded(archive, cached: false))
            } catch {
                logger.error("failed to open archive from link. id=\(id) \(error)")
                await send(.setErrorMessage(String(localized: "error.deeplink.archive")))
            }
        }
    }

    private func tankoubonArchiveItem(id: String) async throws -> ArchiveItem {
        let tankoubon = try await service.retrieveFullTankoubon(id: id).value.result
        return ArchiveItem(
            id: tankoubon.id,
            name: tankoubon.name ?? "",
            extension: "",
            tags: tankoubon.tags ?? "",
            isNew: false,
            progress: tankoubon.progress ?? 0,
            pagecount: tankoubon.fullData?.reduce(0) { $0 + $1.pagecount } ?? 0,
            dateAdded: nil
        )
    }

    @Reducer
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
        UIAppTabView(store: store)
            .ignoresSafeArea()
            .modifier(Covers(store: store))
            .onChange(of: scenePhase) {
                if !store.storedPasscode.isEmpty && scenePhase != .active && store.destination == nil {
                    _ = withTransaction(self.noAnimationTransaction) {
                        store.send(.showLockScreen)
                    }
                }
            }
            .onOpenURL { url in
                store.send(.openURL(url))
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
            .onChange(of: store.successMessage) {
                if !store.successMessage.isEmpty {
                    showNotificationBanner(
                        title: String(localized: "success"),
                        subtitle: store.successMessage,
                        style: .success
                    )
                    store.send(.setSuccessMessage(""))
                }
            }
    }
}

// Stupid SwiftUI will complain 'The compiler is unable to type-check this expression in reasonable time' otherwise
struct Covers: ViewModifier {
    @Bindable var store: StoreOf<AppFeature>

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                item: $store.scope(\.$destination, action: \.destination).login
            ) { store in
                LANraragiConfigView(store: store)
            }
            .fullScreenCover(
                item: $store.scope(\.$destination, action: \.destination).lockScreen
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
}

extension AppFeature.Destination.State: Equatable {}
