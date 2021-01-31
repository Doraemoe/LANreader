//  Created 22/8/20.

import SwiftUI

struct ContentView: View {
    @AppStorage(SettingsKey.lanraragiUrl) var url: String = ""

    @StateObject var contentViewModel = ContentViewModel()

    var body: some View {
        VStack(alignment: .leading) {
            NavigationView {
                if contentViewModel.notLoggedIn {
                    LANraragiConfigView(notLoggedIn: $contentViewModel.notLoggedIn)
                } else {
                    TabView(selection: $contentViewModel.tabName) {
                        LibraryList()
                            .tabItem {
                                Image(systemName: "books.vertical")
                                Text("library")
                            }.tag("library")
                        CategoryList(editMode: $contentViewModel.editMode)
                            .tabItem {
                                Image(systemName: "folder")
                                Text("category")
                            }.tag("category")
                        SearchView()
                            .tabItem {
                                Image(systemName: "magnifyingglass")
                                Text("search")
                            }.tag("search")
                        SettingsView()
                            .tabItem {
                                Image(systemName: "gearshape")
                                Text("settings")
                            }.tag("settings")
                    }
                    .navigationBarTitle(Text(NSLocalizedString(self.contentViewModel.tabName,
                                                               comment: "Force use NSLocalizedString")),
                                        displayMode: .inline)
                    .navigationBarItems(trailing: self.contentViewModel.tabName == "category"
                                            ? AnyView(EditButton()) : AnyView(EmptyView()))
                    .environment(\.editMode, self.$contentViewModel.editMode)
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
