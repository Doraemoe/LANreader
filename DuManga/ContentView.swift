//  Created 22/8/20.

import SwiftUI
import NotificationBannerSwift

struct ContentView: View {
    @State var contentViewModel = ContentViewModel()

    var body: some View {
        TabView(selection: $contentViewModel.tabName) {
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
                SearchView()
            }
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("search")
                    }
                    .tag("search")
            NavigationStack {
                SettingsView()
                        .navigationBarTitle("settings")
                        .navigationBarTitleDisplayMode(.inline)
            }
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
