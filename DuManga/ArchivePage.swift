//  Created 23/8/20.

import SwiftUI

struct ArchivePage: View {
    @State var currentPage = Image("placeholder")
    @State var currentIndex = 0
    @State var allPages = [String]()
    @State var navBarHidden = true
    let id: String
    
    private let config: [String: String]
    private let client: LANRaragiClient
    
    init(id: String) {
        self.id = id
        self.config = UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String] ?? [String: String]()
        self.client = LANRaragiClient(url: config["url"]!, apiKey: config["apiKey"]!)
    }
    
    var body: some View {
        ZStack {
            currentPage
                .resizable()
                .scaledToFit()
                .navigationBarHidden(navBarHidden)
                .navigationBarTitle("")
                .onAppear(perform: { self.postExtract(id: self.id)})
            HStack {
                Rectangle()
                    .opacity(0.0001) // opaque object does not response to tap event
                    .contentShape(Rectangle())
                    .onTapGesture(perform: nextPage)
                Rectangle()
                    .opacity(0.0001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: {self.navBarHidden.toggle()})
                Rectangle()
                    .opacity(0.0001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: previousPage)
            }
        }
        
    }
    
    func postExtract(id: String) {
        client.postArchiveExtract(id: id) { (response: ArchiveExtractResponse?) in
            if let res = response {
                for (index, page) in res.pages.enumerated() {
                    let normalizedPage = String(page.dropFirst(2))
                    self.allPages.append(normalizedPage)
                    if (index == 0) {
                        self.client.getArchivePage(page: normalizedPage) {
                            (image: UIImage?) in
                            if let img = image {
                                self.currentPage = Image(uiImage: img)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func nextPage() {
        currentIndex += 1
        if currentIndex < allPages.count {
            client.getArchivePage(page: allPages[currentIndex]) {
                (image: UIImage?) in
                if let img = image {
                    self.currentPage = Image(uiImage: img)
                }
            }
        }
    }
    
    func previousPage() {
        currentIndex -= 1
        if currentIndex >= 0 {
            client.getArchivePage(page: allPages[currentIndex]) {
                (image: UIImage?) in
                if let img = image {
                    self.currentPage = Image(uiImage: img)
                }
            }
        }
    }
}

struct ArchivePage_Previews: PreviewProvider {
    static var previews: some View {
        let config = ["url": "http://localhost", "apiKey": "apiKey"]
        UserDefaults.standard.set(config, forKey: "LANraragi")
        return ArchivePage(id: "id")
    }
}
