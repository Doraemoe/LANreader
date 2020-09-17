//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchivePageContainer: View {
    @EnvironmentObject var store: AppStore

    let item: ArchiveItem
    var lastPage: String?

    init(item: ArchiveItem) {
        self.item = item
    }

    var body: some View {
        ArchivePage(item: item,
                pages: self.store.state.archive.archivePages[item.id],
                loading: self.store.state.archive.loading,
                tapLeft: self.store.state.setting.tapLeft,
                tapMiddle: self.store.state.setting.tapMiddle,
                tapRight: self.store.state.setting.tapRight,
                swipeLeft: self.store.state.setting.swipeLeft,
                swipeRight: self.store.state.setting.swipeRight,
                splitPage: self.store.state.setting.splitPage,
                splitPagePriorityLeft: self.store.state.setting.splitPagePriorityLeft,
                errorCode: self.store.state.archive.errorCode,
                reset: self.resetState)
                .onAppear(perform: self.load)
    }

    private func load() {
        if self.store.state.archive.archivePages[item.id]?.isEmpty ?? true {
            self.store.dispatch(.archive(action: .extractArchive(id: item.id)))
        }
    }

    private func resetState() {
        self.store.dispatch(.archive(action: .resetState))
    }
}

struct ArchivePage: View {

    @ObservedObject private var internalModel = InternalPageModel()


    private let pages: [String]?
    private let item: ArchiveItem
    private let loading: Bool
    private let tapLeft: PageControl
    private let tapMiddle: PageControl
    private let tapRight: PageControl
    private let swipeLeft: PageControl
    private let swipeRight: PageControl
    private let splitPage: Bool
    private let splitPagePriorityLeft: Bool
    private let errorCode: ErrorCode?
    private let reset: () -> Void

    init(item: ArchiveItem,
         pages: [String]?,
         loading: Bool,
         tapLeft: PageControl,
         tapMiddle: PageControl,
         tapRight: PageControl,
         swipeLeft: PageControl,
         swipeRight: PageControl,
         splitPage: Bool,
         splitPagePriorityLeft: Bool,
         errorCode: ErrorCode?,
         reset: @escaping () -> Void) {
        self.item = item
        self.pages = pages
        self.loading = loading
        self.tapLeft = tapLeft
        self.tapMiddle = tapMiddle
        self.tapRight = tapRight
        self.swipeLeft = swipeLeft
        self.swipeRight = swipeRight
        self.splitPage = splitPage
        self.splitPagePriorityLeft = splitPagePriorityLeft
        self.errorCode = errorCode
        self.reset = reset
        self.loadStartImage()
    }

    var body: some View {
        handleError()
        return GeometryReader { geometry in
            ZStack {
                self.internalModel.currentImage
                        .resizable()
                        .scaledToFit()
                        .aspectRatio(contentMode: .fit)
                        .navigationBarHidden(self.internalModel.controlUiHidden)
                        .navigationBarTitle("")
                        .navigationBarItems(trailing: NavigationLink(destination: ArchiveDetails(item: self.item)) {
                            Text("details")
                        })
                HStack {
                    Rectangle()
                            .opacity(0.0001) // opaque object does not response to tap event
                            .contentShape(Rectangle())
                            .onTapGesture(perform: { self.performAction(self.tapLeft) })
                    Rectangle()
                            .opacity(0.0001)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: { self.performAction(self.tapMiddle) })
                    Rectangle()
                            .opacity(0.0001)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: { self.performAction(self.tapRight) })
                }
                        .gesture(DragGesture(minimumDistance: 50, coordinateSpace: .global).onEnded { value in
                            if value.translation.width < 0 {
                                self.performAction(self.swipeLeft)
                            } else if value.translation.width > 0 {
                                self.performAction(self.swipeRight)
                            }
                        })
                VStack {
                    Spacer()
                    VStack {
                        Text(String(format: "%.0f/%d",
                                self.internalModel.currentIndex + 1,
                                self.pages?.count ?? 0))
                                .bold()
                        Slider(value: self.$internalModel.currentIndex, in: self.getSliderRange(), step: 1) { onSlider in
                            if (!onSlider) {
                                self.jumpToPage(self.internalModel.currentIndex, action: .jump)
                            }
                        }
                                .padding(.horizontal)
                    }
                            .padding()
                            .background(Color.primary.colorInvert().opacity(self.internalModel.controlUiHidden ? 0 : 0.9))
                            .opacity(self.internalModel.controlUiHidden ? 0 : 1)
                }
                VStack {
                    Text("loading")
                    ActivityIndicator(isAnimating: self.loading, style: .large)
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary)
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(self.loading ? 1 : 0)
            }
        }
    }

    private func getIntPart(_ number: Double) -> Int {
        Int(exactly: number.rounded()) ?? 0
    }

    func loadStartImage() {
        if self.pages != nil {
            self.jumpToPage(self.internalModel.currentIndex, action: .next)
        }
    }

    func getSliderRange() -> ClosedRange<Double> {
        0...Double((self.pages?.count ?? 2) - 1)
    }

    func performAction(_ action: PageControl) {
        switch action {
        case .next:
            nextPage()
        case .previous:
            previousPage()
        case .navigation:
            self.internalModel.controlUiHidden.toggle()
        }
    }

    func nextPage() {
        jumpToPage(self.internalModel.currentIndex + 1, action: .next)
    }

    func previousPage() {
        jumpToPage(self.internalModel.currentIndex - 1, action: .previous)
    }

    func jumpToPage(_ page: Double, action: PageFlipAction) {
        if UIDevice.current.orientation.isPortrait {
            if self.internalModel.isCurrentSplittingPage == .first && action == .next {
                nextInternalPage()
                return
            } else if self.internalModel.isCurrentSplittingPage == .last && action == .previous {
                previousInternalPage()
                return
            }
        }
        self.internalModel.isCurrentSplittingPage = .off
        let index = getIntPart(page)
        if (0..<(self.pages?.count ?? 1)).contains(index) {
            self.internalModel.load(page: pages![index],
                    split: self.splitPage && UIDevice.current.orientation.isPortrait,
                    priorityLeft: self.splitPagePriorityLeft,
                    action: action)
            self.internalModel.currentIndex = page.rounded()
            if index == (self.pages?.count ?? 0) - 1 {
                self.internalModel.clearNewFlag(id: item.id)
            }
        }
    }

    func nextInternalPage() {
        if self.splitPagePriorityLeft {
            internalModel.setCurrentPageToRight()
        } else {
            internalModel.setCurrentPageToLeft()
        }
        self.internalModel.isCurrentSplittingPage = .last
    }

    func previousInternalPage() {
        if self.splitPagePriorityLeft {
            internalModel.setCurrentPageToLeft()
        } else {
            internalModel.setCurrentPageToRight()
        }
        self.internalModel.isCurrentSplittingPage = .first
    }

    func jumpToInternalPage(action: PageFlipAction) {
        switch action {
        case .next, .jump:
            if self.splitPagePriorityLeft {
                internalModel.setCurrentPageToLeft()
            } else {
                internalModel.setCurrentPageToRight()
            }
            self.internalModel.isCurrentSplittingPage = .first
        case .previous:
            if self.splitPagePriorityLeft {
                internalModel.setCurrentPageToRight()
            } else {
                internalModel.setCurrentPageToLeft()
            }
            self.internalModel.isCurrentSplittingPage = .last
        }
    }

    func handleError() {
        if let error = self.errorCode {
            switch error {
            case .archiveExtractError:
                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                        subtitle: NSLocalizedString("error.load.page", comment: "list error"),
                        style: .danger)
                banner.show()
                reset()
            default:
                break
            }
        }
    }
}

//struct ArchivePage_Previews: PreviewProvider {
//    static var previews: some View {
//        let config = ["url": "http://localhost", "apiKey": "apiKey"]
//        UserDefaults.standard.set(config, forKey: "LANraragi")
//        return ArchivePage(item: ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder")))
//    }
//}
