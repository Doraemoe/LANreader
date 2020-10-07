//  Created 22/8/20.

import SwiftUI

struct ContentView: View {
    @AppStorage(SettingsKey.lanraragiUrl) var url: String = ""

    @StateObject var contentViewModel = ContentViewModel()

    var body: some View {
        VStack(alignment: .leading) {
            if self.url.isEmpty {
                LANraragiConfigView()
            } else {
                NavigationView {
                    TabView(selection: $contentViewModel.tabName) {
                        LibraryList()
                            .tabItem {
                                Text("library")
                        }.tag("library")
                        CategoryList(editMode: $contentViewModel.editMode)
                            .tabItem {
                                Text("category")
                        }.tag("category")
                        SearchView()
                            .tabItem {
                                Text("search")
                        }.tag("search")
                        SettingsView()
                            .tabItem {
                                Text("settings")
                        }.tag("settings")
                    }
                    .navigationBarTitle(Text(NSLocalizedString(self.contentViewModel.tabName,
                            comment: "String will not be localized without force use NSLocalizedString")),
                            displayMode: .inline)
                    .navigationBarItems(trailing: self.contentViewModel.tabName == "category"
                            ? AnyView(EditButton()) : AnyView(EmptyView()))
                    .environment(\.editMode, self.$contentViewModel.editMode)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
