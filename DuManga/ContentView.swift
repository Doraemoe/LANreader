//  Created 22/8/20.

import SwiftUI

struct ContentView: View {
    @AppStorage(SettingsKey.lanraragiUrl) var url: String = ""

    @StateObject var contentViewModel = ContentViewModel()

    var body: some View {
        VStack(alignment: .leading) {
                if contentViewModel.notLoggedIn {
                        LANraragiConfigView(notLoggedIn: $contentViewModel.notLoggedIn)
                } else {
                    TabView(selection: $contentViewModel.tabName) {
                        NavigationStack {
                            LibraryList()
                                    .navigationBarTitle("library", displayMode: .inline)
                        }
                            .tabItem {
                                Image(systemName: "books.vertical")
                                Text("library")
                            }.tag("library")
                        NavigationStack {
                            CategoryList()
                        }
                            .tabItem {
                                Image(systemName: "folder")
                                Text("category")
                            }.tag("category")
                        NavigationStack {
                            SearchView()
                        }
                            .tabItem {
                                Image(systemName: "magnifyingglass")
                                Text("search")
                            }.tag("search")
                        NavigationStack {
                            SettingsView()
                                    .navigationBarTitle("settings", displayMode: .inline)
                        }
                            .tabItem {
                                Image(systemName: "gearshape")
                                Text("settings")
                            }.tag("settings")
                    }
                }
        }
    }
}
