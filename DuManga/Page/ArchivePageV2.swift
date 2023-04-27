//
// Created on 14/4/21.
//

import SwiftUI
import NotificationBannerSwift

struct AnchorsKey: PreferenceKey {
    // Each key is a row index. The corresponding value is the
    // .center anchor of that row.
    typealias Value = [Int: Anchor<CGPoint>]

    static var defaultValue: Value { [:] }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

struct ArchivePageV2: View {
    @AppStorage(SettingsKey.tapLeftKey) var tapLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.tapMiddleKey) var tapMiddle: String = PageControl.navigation.rawValue
    @AppStorage(SettingsKey.tapRightKey) var tapRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.verticalReader) var verticalReader: Bool = false

    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @StateObject private var archivePageModel = ArchivePageModelV2()

    @State private var verticalScrollTarget: Double?
    @State private var prefetchRequested = false

    let archiveItem: ArchiveItem

    init(archiveItem: ArchiveItem) {
        self.archiveItem = archiveItem
    }

    var body: some View {
        let pages = archivePageModel.archivePages[archiveItem.id]
        return GeometryReader { geometry in
            ZStack {
                if verticalReader {
                    if pages?.isEmpty == false {
                        GeometryReader { scrollGeo in
                            ScrollView {
                                ScrollViewReader { reader in
                                    LazyVStack {
                                        ForEach(0..<pages!.count, id: \.self) { index in
                                            PageImage(id: pages![index]).id(Double(index))
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: geometry.size.width)
                                                    .anchorPreference(key: AnchorsKey.self, value: .center) {
                                                        [index: $0]
                                                    }
                                        }
                                    }
                                            .onTapGesture(perform: { performAction(tapMiddle) })
                                            .onAppear(perform: {
                                                reader.scrollTo(archivePageModel.currentIndex, anchor: .top)
                                            })
                                            .onChange(of: verticalScrollTarget) { target in
                                                if let target = target {
                                                    verticalScrollTarget = nil
                                                    reader.scrollTo(target, anchor: .top)
                                                }
                                            }
                                }

                            }
                                    .onPreferenceChange(AnchorsKey.self) { anchors in
                                        let topIndex = topRow(of: anchors, in: scrollGeo) ?? 0
                                        if topIndex != 0 && topIndex != archivePageModel.currentIndex.int {
                                            archivePageModel.currentIndex = Double(topIndex)
                                        }
                                    }
                                    .navigationBarHidden(archivePageModel.controlUiHidden)
                                    .navigationBarTitle("")
                                    .navigationBarItems(trailing: NavigationLink(
                                            destination: ArchiveDetails(item: archiveItem)) {
                                        Text("details")
                                    })
                        }
                    } else {
                        Image("placeholder")
                    }
                } else {
                    if pages?.isEmpty == false {
                        TabView(selection: self.$archivePageModel.currentIndex) {
                            ForEach(0..<pages!.count, id: \.self) { index in
                                PageImage(id: pages![index]).tag(Double(index))
                                        .scaledToFit()
                                        .aspectRatio(contentMode: .fit)
                                        .draggableAndZoomable(
                                                contentSize: CGSize(width: geometry.size.width,
                                                        height: geometry.size.height))
                            }
                        }
                                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                                .navigationBarHidden(archivePageModel.controlUiHidden)
                                .navigationBarTitle("")
                                .navigationBarItems(trailing: NavigationLink(
                                        destination: ArchiveDetails(item: archiveItem)) {
                                    Text("details")
                                })
                    } else {
                        Image("placeholder")
                    }
                    HStack {
                        Rectangle()
                                .opacity(0.0001) // opaque object does not response to tap event
                                .contentShape(Rectangle())
                                .onTapGesture(perform: { performAction(tapLeft) })
                        Rectangle()
                                .opacity(0.0001)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: { performAction(tapMiddle) })
                        Rectangle()
                                .opacity(0.0001)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: { performAction(tapRight) })
                    }
                }
                VStack {
                    Spacer()
                    VStack {
                        Text(String(format: "%.0f/%d",
                                archivePageModel.currentIndex + 1,
                                pages?.count ?? 0))
                                .bold()
                        Slider(value: self.$archivePageModel.currentIndex,
                                in: 0...Double((pages?.count ?? 2) - 1),
                                step: 1) { onSlider in
                            if !onSlider {
                                verticalScrollTarget = archivePageModel.currentIndex
                            }
                        }
                                .padding(.horizontal)
                    }
                            .padding()
                            .background(Color.primary.colorInvert()
                                    .opacity(archivePageModel.controlUiHidden ? 0 : 0.9))
                            .opacity(archivePageModel.controlUiHidden ? 0 : 1)
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
                        extractArchive()
                    })
                    .onChange(of: archivePageModel.archiveItems) { _ in
                        if !archivePageModel.verifyArchiveExists(id: archiveItem.id) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .onChange(of: archivePageModel.errorCode) { errorCode in
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
                    }
                    .onChange(of: archivePageModel.currentIndex) { index in
                        store.dispatch(.archive(action: .updateReadProgressServer(
                                id: archiveItem.id, progress: index.int + 1)))
                        if index.int == (archivePageModel.archiveItems[archiveItem.id]?.pagecount ?? 0) - 1 {
                            archivePageModel.clearNewFlag(id: archiveItem.id)
                        }
                    }
                    .onChange(of: archivePageModel.archivePages) { pages in
                        if let ids = pages[archiveItem.id] {
                            if !prefetchRequested && !ids.isEmpty {
                                prefetchRequested = true
                                archivePageModel.prefetchImages(ids: ids)
                            }
                        }
                    }
                    .onDisappear {
                        prefetchRequested = false
                        archivePageModel.unload()
                    }
        }
    }

    private func topRow(of anchors: AnchorsKey.Value, in proxy: GeometryProxy) -> Int? {
        var yBest = CGFloat.infinity
        var answer: Int?
        for (row, anchor) in anchors {
            let yAxis = proxy[anchor].y
            guard yAxis >= 0, yAxis < yBest else { continue }
            answer = row
            yBest = yAxis
        }
        return answer
    }

    private func extractArchive() {
        if archivePageModel.archivePages[archiveItem.id]?.isEmpty ?? true {
            store.dispatch(.page(action: .extractArchive(id: archiveItem.id)))
        }
    }

    func performAction(_ action: String) {
        switch action {
        case PageControl.next.rawValue:
            let currentIndexInt = archivePageModel.currentIndex.int
            let pageNumbers = archivePageModel.archivePages[archiveItem.id]?.count ?? 1
            if currentIndexInt < pageNumbers - 1 {
                archivePageModel.currentIndex += 1
            }
        case PageControl.previous.rawValue:
            if archivePageModel.currentIndex > 0 {
                archivePageModel.currentIndex -= 1
            }
        case PageControl.navigation.rawValue:
            archivePageModel.controlUiHidden.toggle()
        default:
            // This should not happen
            break
        }
    }

}
