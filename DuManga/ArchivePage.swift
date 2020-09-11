//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

enum InternalPageSplitState: String, CaseIterable {
    case off
    case first
    case last
}

enum PageFlipAction: String, CaseIterable {
    case next
    case previous
    case jump
}

struct ArchivePage: View {
    
    static let extractErrorBanner = NotificationBanner(title: NSLocalizedString("error", comment: "error"), subtitle: NSLocalizedString("error.extract", comment: "extract error"), style: .danger)
    static let loadPageErrorBanner = NotificationBanner(title: NSLocalizedString("error", comment: "error"), subtitle: NSLocalizedString("error.load.page", comment: "load page error"), style: .danger)
    
    @State var currentPage = Image("placeholder")
    @State var currentIndex: Double = 0
    @State var allPages = [String]()
    @State var controlUiHidden = true
    @State var isLoading = false
    @State var leftHalfPage = Image("placeholder")
    @State var rightHalfPage = Image("placeholder")
    @State var isCurrentSplittingPage = InternalPageSplitState.off
    
    let item: ArchiveItem
    
    private let client: LANRaragiClient
    
    init(item: ArchiveItem) {
        self.item = item
        self.client = LANRaragiClient(url: UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl)!,
                apiKey: UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey)!)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                self.currentPage
                    .resizable()
                    .scaledToFit()
                    .navigationBarHidden(self.controlUiHidden)
                    .navigationBarTitle("")
                    .navigationBarItems(trailing: NavigationLink(destination: ArchiveDetails(item: self.item)) { Text("details") })
                    .onAppear(perform: { self.postExtract(id: self.item.id)})
                HStack {
                    Rectangle()
                        .opacity(0.0001) // opaque object does not response to tap event
                        .contentShape(Rectangle())
                        .onTapGesture(perform: { self.performActionBasedOnSettings(key: SettingsKey.tapLeftKey, defaultAction: .next) })
                    Rectangle()
                        .opacity(0.0001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: { self.performActionBasedOnSettings(key: SettingsKey.tapMiddleKey, defaultAction: .navigation) })
                    Rectangle()
                        .opacity(0.0001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: { self.performActionBasedOnSettings(key: SettingsKey.tapRightKey, defaultAction: .previous) })
                }
                .gesture(DragGesture(minimumDistance: 50, coordinateSpace: .global).onEnded { value in
                    if value.translation.width < 0 {
                        self.performActionBasedOnSettings(key: SettingsKey.swipeLeftKey, defaultAction: .next)
                    }
                    else if value.translation.width > 0 {
                        self.performActionBasedOnSettings(key: SettingsKey.swipeRightKey, defaultAction: .previous)
                    }
                })
                VStack {
                    Spacer()
                    VStack {
                        Text(String(format: "%.0f/%d", self.currentIndex + 1, self.allPages.count))
                            .bold()
                        Slider(value: self.$currentIndex, in: self.getSliderRange(), step: 1) { onSlider in
                            if (!onSlider) {
                                self.jumpToPage(self.currentIndex, action: .jump)
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
        if !allPages.isEmpty {
            return
        }
        self.isLoading = true
        client.postArchiveExtract(id: id) { (response: ArchiveExtractResponse?) in
            if let res = response {
                for (index, page) in res.pages.enumerated() {
                    let normalizedPage = String(page.dropFirst(2))
                    self.allPages.append(normalizedPage)
                    if (index == 0) {
                        self.jumpToPage(Double(index), action: .next)
                    }
                }
            } else {
                ArchivePage.extractErrorBanner.show()
            }
            self.isLoading = false
        }
    }
    
    func nextPage() {
        jumpToPage(currentIndex + 1, action: .next)
    }
    
    func previousPage() {
        jumpToPage(currentIndex - 1, action: .previous)
    }
    
    func jumpToPage(_ page: Double, action: PageFlipAction) {
        if UIDevice.current.orientation.isPortrait {
            if self.isCurrentSplittingPage == .first && action == .next {
                nextInternalPage()
                return
            } else if self.isCurrentSplittingPage == .last && action == .previous {
                previousInternalPage()
                return
            }
        }
        self.isCurrentSplittingPage = .off
        let index = getIntPart(page)
        if (0..<self.allPages.count).contains(index) {
            client.getArchivePage(page: allPages[index]) {
                (image: UIImage?) in
                if let img = image {
                    if UserDefaults.standard.bool(forKey: SettingsKey.splitPage)
                        && UIDevice.current.orientation.isPortrait
                        && img.size.width / img.size.height > 1.2 {
                        let success = self.cropAndSetInternalImage(image: img)
                        if success {
                            self.jumpToInternalPage(action: action)
                        } else {
                            ArchivePage.loadPageErrorBanner.show()
                            self.currentPage = Image("placeholder")
                        }
                    } else {
                        self.currentPage = Image(uiImage: img)
                    }
                } else {
                    ArchivePage.loadPageErrorBanner.show()
                    self.currentPage = Image("placeholder")
                }
                self.currentIndex = page.rounded()
                if index == self.allPages.count - 1 {
                    self.client.clearNewFlag(id: self.item.id) { success in
                        // NO-OP
                        return
                    }
                }
            }
        }
    }
    
    func nextInternalPage() {
        if UserDefaults.standard.bool(forKey: SettingsKey.splitPagePriorityLeft) {
            self.currentPage = self.rightHalfPage
        } else {
            self.currentPage = self.leftHalfPage
        }
        self.isCurrentSplittingPage = .last
    }
    
    func previousInternalPage() {
        if UserDefaults.standard.bool(forKey: SettingsKey.splitPagePriorityLeft) {
            self.currentPage = self.leftHalfPage
        } else {
            self.currentPage = self.rightHalfPage
        }
        self.isCurrentSplittingPage = .first
    }
    
    func jumpToInternalPage(action: PageFlipAction) {
        switch action {
        case .next, .jump:
            if UserDefaults.standard.bool(forKey: SettingsKey.splitPagePriorityLeft) {
                self.currentPage = self.leftHalfPage
            } else {
                self.currentPage = self.rightHalfPage
            }
            self.isCurrentSplittingPage = .first
        case .previous:
            if UserDefaults.standard.bool(forKey: SettingsKey.splitPagePriorityLeft) {
                self.currentPage = self.rightHalfPage
            } else {
                self.currentPage = self.leftHalfPage
            }
            self.isCurrentSplittingPage = .last
        }
    }
    
    func cropAndSetInternalImage(image: UIImage) -> Bool {
        if let cgImage = image.cgImage {
            if let leftHalf = cgImage.cropping(to: CGRect(x: 0, y: 0, width: cgImage.width / 2, height: cgImage.height)) {
                self.leftHalfPage = Image(uiImage: UIImage(cgImage: leftHalf))
            } else {
                return false
            }
            if let rightHalf = cgImage.cropping(to: CGRect(x: cgImage.width / 2, y: 0, width: cgImage.width, height: cgImage.height)) {
                self.rightHalfPage = Image(uiImage: UIImage(cgImage: rightHalf))
            } else {
                return false
            }
        } else {
            return false
        }
        return true
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
        return ArchivePage(item: ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder")))
    }
}
