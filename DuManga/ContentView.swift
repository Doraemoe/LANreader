//  Created 22/8/20.
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift

struct ContentView: View {
    let store: StoreOf<AppFeature>
    @State var contentViewModel = ContentViewModel()

    struct ViewState: Equatable {
        @BindingViewState var tabName: String
        init(bindingViewStore: BindingViewStore<AppFeature.State>) {
            self._tabName = bindingViewStore.$tabName
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            TabView(selection: viewStore.$tabName) {
                NavigationStack {
                    LibraryList()
                        .navigationTitle("library")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Image(systemName: "books.vertical")
                    Text("library")
                }
                .tag("library")
                NavigationStack {
                    CategoryList()
                }
                .tabItem {
                    Image(systemName: "folder")
                    Text("category")
                }
                .tag("category")
                NavigationStack {
                    SearchViewV2(store: store.scope(state: \.search, action: {
                        .search($0)
                    }))
                }
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
