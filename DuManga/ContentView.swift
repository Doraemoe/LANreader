//  Created 22/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""

    let store: StoreOf<AppFeature>

    @State var contentViewModel = ContentViewModel()
    private let noAnimationTransaction: Transaction

    struct ViewState: Equatable {
        @BindingViewState var tabName: String
        let destination: AppFeature.Destination.State?
        init(bindingViewStore: BindingViewStore<AppFeature.State>) {
            self._tabName = bindingViewStore.$tabName
            self.destination = bindingViewStore.destination
        }
    }

    init(store: StoreOf<AppFeature>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        self.noAnimationTransaction = transaction

        self.store = store
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            TabView(selection: viewStore.$tabName) {
                LibraryListV2(store: store.scope(state: \.library, action: {
                    .library($0)
                }))
                .tabItem {
                    Image(systemName: "books.vertical")
                    Text("library")
                }
                .tag("library")
                CategoryListV2(store: store.scope(state: \.category, action: {
                    .category($0)
                }))
                .tabItem {
                    Image(systemName: "folder")
                    Text("category")
                }
                .tag("category")
                SearchViewV2(store: store.scope(state: \.search, action: {
                    .search($0)
                }))
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("search")
                }
                .tag("search")
                SettingsView(store: store.scope(state: \.settings, action: {
                    .settings($0)
                }))
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("settings")
                }
                .tag("settings")
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
                Task {
                    let (success, message) = await contentViewModel.queueUrlDownload(url: url)
                    if success {
                        let banner = NotificationBanner(
                            title: NSLocalizedString("success", comment: "success"),
                            subtitle: message,
                            style: .success
                        )
                        banner.show()
                    } else {
                        let banner = NotificationBanner(
                            title: NSLocalizedString("error", comment: "error"),
                            subtitle: message,
                            style: .danger
                        )
                        banner.show()
                    }
                }
            }
        }
    }
}
