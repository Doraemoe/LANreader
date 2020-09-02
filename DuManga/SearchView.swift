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
                        .padding(.leading, 8)
                    TextField("Search", text: $keyword, onEditingChanged: { change in
                        if change {
                            self.showSearchResult = false
                        } else {
                            self.showSearchResult = true
                        }
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.trailing, 8)
                    
                }
                .onAppear(perform: { self.navBarTitle = "search" })
                if !showSearchResult {
                    Spacer()
                }
            }
            if showSearchResult {
                ArchiveList(navBarTitle: self.$navBarTitle, searchKeyword: self.keyword)
            }
        }
        
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView(navBarTitle: Binding.constant("search"))
    }
}
