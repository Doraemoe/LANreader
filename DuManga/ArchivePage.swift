//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchivePage: View {
    @AppStorage(SettingsKey.tapLeftKey) var tapLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.tapMiddleKey) var tapMiddle: String = PageControl.navigation.rawValue
    @AppStorage(SettingsKey.tapRightKey) var tapRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.swipeLeftKey) var swipeLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.swipeRightKey) var swipeRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.splitPage) var splitPage: Bool = false
    @AppStorage(SettingsKey.splitPagePriorityLeft) var splitPagePriorityLeft: Bool = false

    @EnvironmentObject var store: AppStore

    @StateObject private var archivePageModel = ArchivePageModel()

    let archiveItem: ArchiveItem

    init(archiveItem: ArchiveItem) {
        self.archiveItem = archiveItem
    }

    var body: some View {
        let pages = archivePageModel.archivePages[archiveItem.id]
        return GeometryReader { geometry in
            ZStack {
                self.archivePageModel.currentImage
                        .resizable()
                        .scaledToFit()
                        .aspectRatio(contentMode: .fit)
                        .navigationBarHidden(self.archivePageModel.controlUiHidden)
                        .navigationBarTitle("")
                        .navigationBarItems(trailing: NavigationLink(destination: ArchiveDetails(item: archiveItem)) {
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
                                self.archivePageModel.currentIndex + 1,
                                pages?.count ?? 0))
                                .bold()
                        Slider(value: self.$archivePageModel.currentIndex,
                                in: 0...Double((pages?.count ?? 2) - 1),
                                step: 1) { onSlider in
                            if !onSlider {
                                self.jumpToPage(self.archivePageModel.currentIndex, action: .jump)
                            }
                        }
                                .padding(.horizontal)
                    }
                            .padding()
                            .background(Color.primary.colorInvert()
                                    .opacity(self.archivePageModel.controlUiHidden ? 0 : 0.9))
                            .opacity(self.archivePageModel.controlUiHidden ? 0 : 1)
                }
                VStack {
                    Text("loading")
                    ProgressView()
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary)
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(archivePageModel.loading ? 1 : 0)
            }
                    .onAppear(perform: {
                        archivePageModel.load(state: store.state,
                                              progress: archiveItem.progress > 0 ? archiveItem.progress - 1 : 0)
                        self.extractArchive()
                    })
                    .onChange(of: archivePageModel.archivePages[archiveItem.id], perform: { page in
                        if page != nil {
                            self.jumpToPage(self.archivePageModel.currentIndex, action: .next)
                        }
                    })
                    .onChange(of: archivePageModel.errorCode, perform: { errorCode in
                        if errorCode != nil {
                            switch errorCode! {
                            case .archiveExtractError:
                                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                        subtitle: NSLocalizedString("error.extract", comment: "list error"),
                                        style: .danger)
                                banner.show()
                                store.dispatch(.page(action: .resetState))
                            case .archiveFetchPageError:
                                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                        subtitle: NSLocalizedString("error.load.page", comment: "list error"),
                                        style: .danger)
                                banner.show()
                                store.dispatch(.page(action: .resetState))
                            default:
                                break
                            }
                        }
                    })
        }
    }

    private func extractArchive() {
        if archivePageModel.archivePages[archiveItem.id]?.isEmpty ?? true {
            self.store.dispatch(.page(action: .extractArchive(id: archiveItem.id)))
        }
    }

    private func getIntPart(_ number: Double) -> Int {
        Int(exactly: number.rounded()) ?? 0
    }

    func performAction(_ action: String) {
        switch action {
        case PageControl.next.rawValue:
            nextPage()
        case PageControl.previous.rawValue:
            previousPage()
        case PageControl.navigation.rawValue:
            self.archivePageModel.controlUiHidden.toggle()
        default:
            // This should not happen
            break
        }
    }

    func nextPage() {
        jumpToPage(self.archivePageModel.currentIndex + 1, action: .next)
    }

    func previousPage() {
        jumpToPage(self.archivePageModel.currentIndex - 1, action: .previous)
    }

    func jumpToPage(_ page: Double, action: PageFlipAction) {
        if UIDevice.current.orientation.isPortrait {
            if self.archivePageModel.isCurrentSplittingPage == .first && action == .next {
                nextInternalPage()
                return
            } else if self.archivePageModel.isCurrentSplittingPage == .last && action == .previous {
                previousInternalPage()
                return
            }
        }
        self.archivePageModel.isCurrentSplittingPage = .off
        let index = getIntPart(page)
        if (0..<(archivePageModel.archivePages[archiveItem.id]?.count ?? 1)).contains(index) {
            self.archivePageModel.loadPage(page: archivePageModel.archivePages[archiveItem.id]![index],
                    split: self.splitPage && UIDevice.current.orientation.isPortrait,
                    priorityLeft: self.splitPagePriorityLeft,
                    action: action, dispatchError: { errorCode in
              store.dispatch(.page(action: .error(error: errorCode)))
            })
            self.archivePageModel.currentIndex = page.rounded()
            store.dispatch(.archive(action: .updateReadProgressServer(id: archiveItem.id, progress: index + 1)))
            if index == (archivePageModel.archivePages[archiveItem.id]?.count ?? 0) - 1 {
                self.archivePageModel.clearNewFlag(id: archiveItem.id)
            }
        }
    }

    func nextInternalPage() {
        if self.splitPagePriorityLeft {
            archivePageModel.setCurrentPageToRight()
        } else {
            archivePageModel.setCurrentPageToLeft()
        }
        self.archivePageModel.isCurrentSplittingPage = .last
    }

    func previousInternalPage() {
        if self.splitPagePriorityLeft {
            archivePageModel.setCurrentPageToLeft()
        } else {
            archivePageModel.setCurrentPageToRight()
        }
        self.archivePageModel.isCurrentSplittingPage = .first
    }

    func jumpToInternalPage(action: PageFlipAction) {
        switch action {
        case .next, .jump:
            if self.splitPagePriorityLeft {
                archivePageModel.setCurrentPageToLeft()
            } else {
                archivePageModel.setCurrentPageToRight()
            }
            self.archivePageModel.isCurrentSplittingPage = .first
        case .previous:
            if self.splitPagePriorityLeft {
                archivePageModel.setCurrentPageToRight()
            } else {
                archivePageModel.setCurrentPageToLeft()
            }
            self.archivePageModel.isCurrentSplittingPage = .last
        }
    }
}

// struct ArchivePage_Previews: PreviewProvider {
//    static var previews: some View {
//        let config = ["url": "http://localhost", "apiKey": "apiKey"]
//        UserDefaults.standard.set(config, forKey: "LANraragi")
//        return ArchivePage(item: ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder")))
//    }
// }
