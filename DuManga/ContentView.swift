//  Created 22/8/20.

import SwiftUI

struct ContentView: View {
    @AppStorage(SettingsKey.lanraragiUrl) var url: String = ""

    @State var navBarTitle: String = ""
    @State var editMode = EditMode.inactive
    @State var tabName: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            if self.url.isEmpty {
                LANraragiConfigView()
            } else {
                NavigationView {
                    TabView(selection: $tabName) {
                        ArchiveList(navBarTitle: $navBarTitle)
                            .tabItem {
                                Text("library")
                        }.tag("library")
                        CategoryList(navBarTitle: $navBarTitle, editMode: $editMode)
                            .tabItem {
                                Text("category")
                        }.tag("category")
                        SearchView(navBarTitle: $navBarTitle)
                            .tabItem {
                                Text("search")
                        }.tag("search")
                        SettingsView(navBarTitle: $navBarTitle)
                            .tabItem {
                                Text("settings")
                        }.tag("settings")
                    }
                    .navigationBarTitle(Text(NSLocalizedString(navBarTitle,
                            comment: "String will not be localized without force use NSLocalizedString")),
                            displayMode: .inline)
                    .navigationBarItems(trailing: self.tabName == "category"
                            ? AnyView(EditButton()) : AnyView(EmptyView()))
                    .environment(\.editMode, self.$editMode)
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
