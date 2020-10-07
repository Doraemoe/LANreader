//Created 2/9/20

import SwiftUI

struct SearchView: View {
    @State var keyword: String = ""
    @State var showSearchResult = false

    var body: some View {
        VStack {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .padding()
                    TextField("search", text: $keyword, onEditingChanged: { change in
                        if change {
                            self.showSearchResult = false
                        } else {
                            self.showSearchResult = true
                        }
                    })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding([.top, .bottom, .trailing])

                }
                if !showSearchResult || self.keyword.isEmpty {
                    Spacer()
                }
            }
            if showSearchResult && !self.keyword.isEmpty {
                SearchResult(keyword: self.keyword)
            }
        }

    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView()
    }
}
