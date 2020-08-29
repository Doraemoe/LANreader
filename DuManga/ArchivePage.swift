//  Created 23/8/20.

import SwiftUI

struct ArchivePage: View {
    @State var currentPage = Image("placeholder")
    @State var currentIndex: Double = 0
    @State var allPages = [String]()
    @State var controlUiHidden = true
    @State var isLoading = false
    
    let id: String
    let tapLeftKey = "settings.read.tap.left"
    let tapMiddleKey = "settings.read.tap.middle"
    let tapRightKey = "settings.read.tap.right"
    let swipeLeftKey = "settings.read.swipe.left"
    let swipeRightKey = "settings.read.swipe.right"
    
    private let config: [String: String]
    private let client: LANRaragiClient
    
    init(id: String) {
        self.id = id
        self.config = UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String] ?? [String: String]()
        self.client = LANRaragiClient(url: config["url"]!, apiKey: config["apiKey"]!)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                self.currentPage
                    .resizable()
                    .scaledToFit()
                    .navigationBarHidden(self.controlUiHidden)
                    .navigationBarTitle("")
                    .onAppear(perform: { self.postExtract(id: self.id)})
                HStack {
                    Rectangle()
                        .opacity(0.0001) // opaque object does not response to tap event
                        .contentShape(Rectangle())
                        .onTapGesture(perform: { self.performActionBasedOnSettings(key: self.tapLeftKey, defaultAction: .next) })
                    Rectangle()
                        .opacity(0.0001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: { self.performActionBasedOnSettings(key: self.tapMiddleKey, defaultAction: .navigation) })
                    Rectangle()
                        .opacity(0.0001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: { self.performActionBasedOnSettings(key: self.tapRightKey, defaultAction: .previous) })
                }
                .gesture(DragGesture(minimumDistance: 50, coordinateSpace: .global).onEnded { value in
                    if value.translation.width < 0 {
                        self.performActionBasedOnSettings(key: self.swipeLeftKey, defaultAction: .next)
                    }
                    else if value.translation.width > 0 {
                        self.performActionBasedOnSettings(key: self.swipeRightKey, defaultAction: .previous)
                    }
                })
                VStack {
                    Spacer()
                    VStack {
                        Text(String(format: "%.0f/%d", self.currentIndex + 1, self.allPages.count))
                            .bold()
                        Slider(value: self.$currentIndex, in: self.getSliderRange(), step: 1) { onSlider in
                            if (!onSlider) {
                                self.jumpToPage(self.currentIndex)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color.primary.colorInvert().opacity(self.controlUiHidden ? 0 : 0.9))
                    .opacity(self.controlUiHidden ? 0 : 1)
                }
                VStack {
                    Text("loading")
                    ActivityIndicator(isAnimating: self.$isLoading, style: .large)
                }
                .frame(width: geometry.size.width / 3,
                       height: geometry.size.height / 5)
                    .background(Color.secondary.colorInvert())
                    .foregroundColor(Color.primary)
                    .cornerRadius(20)
                    .opacity(self.isLoading ? 1 : 0)
            }
        }
    }
    
    func getSliderRange() -> ClosedRange<Double> {
        if self.allPages.isEmpty {
            return 0...1
        } else {
            return 0...Double(self.allPages.count - 1)
        }
    }
    
    func getIntPart(_ number: Double) -> Int {
        return Int(exactly: number.rounded()) ?? 0
    }
    
    func postExtract(id: String) {
        self.isLoading = true
        client.postArchiveExtract(id: id) { (response: ArchiveExtractResponse?) in
            if let res = response {
                for (index, page) in res.pages.enumerated() {
                    let normalizedPage = String(page.dropFirst(2))
                    self.allPages.append(normalizedPage)
                    if (index == 0) {
                        self.jumpToPage(Double(index))
                    }
                }
            }
            self.isLoading = false
        }
    }
    
    func nextPage() {
        jumpToPage(currentIndex + 1)
    }
    
    func previousPage() {
        jumpToPage(currentIndex - 1)
    }
    
    func jumpToPage(_ page: Double) {
        let index = getIntPart(page)
        if (0..<self.allPages.count).contains(index) {
            client.getArchivePage(page: allPages[index]) {
                (image: UIImage?) in
                if let img = image {
                    self.currentPage = Image(uiImage: img)
                } else {
                    self.currentPage = Image("placeholder")
                }
                self.currentIndex = page.rounded()
            }
        }
    }
    
    func performActionBasedOnSettings(key:String, defaultAction: PageControl) {
        let action = PageControl(rawValue: UserDefaults.standard.object(forKey: key) as? String ?? defaultAction.rawValue) ?? defaultAction
        switch action {
        case .next:
            nextPage()
        case .previous:
            previousPage()
        case .navigation:
            self.controlUiHidden.toggle()
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
