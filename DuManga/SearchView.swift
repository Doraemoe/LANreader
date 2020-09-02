//Created 2/9/20

import SwiftUI

struct SearchView: View {
    @State var keyword: String = ""
    @State var showSearchResult = false
    
    @Binding var navBarTitle: String
    
    init(navBarTitle: Binding<String>) {
        self._navBarTitle = navBarTitle
    }
    
    var body: some View {
        VStack {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .padding()
                    TextField("Search", text: $keyword, onEditingChanged: { change in
                        if change {
                            self.showSearchResult = false
                        } else {
                            self.showSearchResult = true
                        }
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding([.top, .bottom, .trailing])
                    
                }
                .onAppear(perform: { self.navBarTitle = "search" })
                if !showSearchResult || self.keyword.isEmpty {
                    Spacer()
                }
            }
            if showSearchResult && !self.keyword.isEmpty {
                ArchiveList(navBarTitle: self.$navBarTitle, searchKeyword: self.keyword, navBarTitleOverride: "search")
            }
        }
        
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView(navBarTitle: Binding.constant("search"))
    }
}
