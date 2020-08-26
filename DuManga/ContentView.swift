//  Created 22/8/20.

import SwiftUI

struct ContentView: View {
    @State var settingView = UserDefaults.standard.dictionary(forKey: "LANraragi") == nil
    @State var navBarTitle: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            if (self.settingView) {
                LANraragiConfigView(settingView: $settingView)
            } else {
                NavigationView {
                    TabView{
                        ArchiveList(navBarTitle: $navBarTitle)
                            .tabItem {
                                Text("library")
                        }
                    }
                    .navigationBarTitle(Text(navBarTitle), displayMode: .inline)
                    .navigationBarItems(trailing:Button(action: {
                        self.settingView.toggle()
                    }) {
                        Text("settings")
                    } )
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        UserDefaults.standard.removeObject(forKey: "LANraragi")
        return ContentView()
    }
}
