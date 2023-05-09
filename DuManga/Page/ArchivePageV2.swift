//
// Created on 14/4/21.
//

import SwiftUI
import NotificationBannerSwift

struct AnchorsKey: PreferenceKey {
    // Each key is a row index. The corresponding value is the
    // .center anchor of that row.
    typealias Value = [Int: Anchor<CGPoint>]

    static var defaultValue: Value {
        [:]
    }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) {
            $1
        }
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

    @State private var verticalScrollTarget: Int?
    @State private var prefetchRequested = false

    let archiveItem: ArchiveItem

    init(archiveItem: ArchiveItem) {
        self.archiveItem = archiveItem
    }

    var body: some View {
        let pages = archivePageModel.archivePages[archiveItem.id] ?? [String]()
        return GeometryReader { geometry in
            ZStack {
                if verticalReader {
                    vReader(pages: pages, geometry: geometry)
                } else {
                    hReader(pages: pages, geometry: geometry)
                }
                if archivePageModel.loading {
                    LoadingView(geometry: geometry)
                }
            }
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button(action: {
                                store.dispatch(
                                    .trigger(action: .pageRefreshAction(
                                        id: pages[archivePageModel.currentIndex])
                                    )
                                )
                            }, label: {
                                Image(systemName: "arrow.clockwise")
                            })
                            NavigationLink("details") {
                                ArchiveDetails(item: archiveItem)
                            }
                        }
                        ToolbarItemGroup(placement: .bottomBar) {
                            bottomToolbar(pages: pages)
                        }
                    }
                    .navigationBarTitle(archiveItem.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(archivePageModel.controlUiHidden ? .hidden : .visible, for: .navigationBar)
                    .toolbar(archivePageModel.controlUiHidden ? .hidden : .visible, for: .bottomBar)
                    .toolbar(.hidden, for: .tabBar)
                    .task {
                        if archivePageModel.archivePages[archiveItem.id]?.isEmpty ?? true {
                            await store.dispatch(extractArchive(id: archiveItem.id))
                        }
                    }
                    .onAppear(perform: {
                        archivePageModel.load(state: store.state,
                                progress: archiveItem.progress > 0 ? archiveItem.progress - 1 : 0)
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
                            default:
                                break
                            }
                        }
                    }
                    .onChange(of: archivePageModel.currentIndex) { index in
                        archivePageModel.sliderIndex = Double(archivePageModel.currentIndex)
                        Task {
                            await onIndexChange(index: index)
                        }

                    }
                    .onChange(of: pages) { [pages] newPages in
                        if pages.isEmpty && !newPages.isEmpty {
                            archivePageModel.prefetchImages(ids: newPages)
                        }
                    }
                    .onDisappear {
                        archivePageModel.unload()
                    }
        }
    }

    private func vReader(pages: [String], geometry: GeometryProxy) -> some View {
        ZStack {
            if pages.isEmpty {
                // This is to make sure when onAppear called on ScrollView there is page to scroll to
                Color.primary.colorInvert()
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack {
                            ForEach(0..<pages.count, id: \.self) { index in
                                PageImage(id: pages[index], geometrySize: geometry.size)
                                        .id(index)
                                        .anchorPreference(key: AnchorsKey.self, value: .center) {
                                            [index: $0]
                                        }
                            }
                        }
                                .onTapGesture(perform: { performAction(tapMiddle) })
                                .onAppear {
                                    reader.scrollTo(archivePageModel.currentIndex, anchor: .top)
                                    archivePageModel.verticalReaderReady = true
                                }
                                .onDisappear {
                                    archivePageModel.verticalReaderReady = false
                                }
                                .onChange(of: verticalScrollTarget) { target in
                                    if let target = target {
                                        reader.scrollTo(target, anchor: .top)
                                    }
                                }
                    }
                }
                        .onPreferenceChange(AnchorsKey.self) { anchors in
                            // This is to prevent incorrectly assign index when page first open
                            if archivePageModel.verticalReaderReady {
                                let topIndex = topRow(of: anchors, in: geometry)
                                if topIndex != nil && topIndex != archivePageModel.currentIndex {
                                    archivePageModel.currentIndex = topIndex!
                                }
                            }

                        }
            }
        }
    }

    private func hReader(pages: [String], geometry: GeometryProxy) -> some View {
        ZStack {
            if pages.isEmpty == false {
                TabView(selection: self.$archivePageModel.currentIndex) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        PageImage(id: pages[index], geometrySize: geometry.size).tag(index)
                    }
                }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .onTapGesture { location in
                            if location.x < geometry.size.width / 3 {
                                performAction(tapLeft)
                            } else if location.x > geometry.size.width / 3 * 2 {
                                performAction(tapRight)
                            } else {
                                performAction(tapMiddle)
                            }
                        }
            } else {
                // If not return a view here, when user click into already extracted archive, TabView will render ALL pages at once
                // However, if return empty view, the loading position will be wrong, thus return a color view
                Color.primary.colorInvert()
            }
        }
    }

    private func bottomToolbar(pages: [String]) -> some View {
        VStack {
            Text(String(format: "%d/%d",
                    archivePageModel.currentIndex + 1,
                    pages.count))
                    .bold()
            Slider(value: self.$archivePageModel.sliderIndex,
                    in: 0...Double(pages.count < 1 ? 1 : pages.count - 1),
                    step: 1) { onSlider in
                if !onSlider {
                    archivePageModel.currentIndex = archivePageModel.sliderIndex.int
                    verticalScrollTarget = archivePageModel.sliderIndex.int
                }
            }
                    .padding(.horizontal)
                    .padding(.bottom, 50)
        }
                .padding()
                .background(Color.primary.colorInvert())
    }

    private func onIndexChange(index: Int) async {
        await store.dispatch(updateReadProgress(
                id: archiveItem.id, progress: index + 1))
        if index == (archivePageModel.archiveItems[archiveItem.id]?.pagecount ?? 0) - 1 {
            await archivePageModel.clearNewFlag(id: archiveItem.id)
        }
    }

    private func topRow(of anchors: AnchorsKey.Value, in proxy: GeometryProxy) -> Int? {
        var yBest = CGFloat.infinity
        var answer: Int?
        for (row, anchor) in anchors {
            let yAxis = proxy[anchor].y
            guard yAxis >= 0, yAxis < yBest else {
                continue
            }
            answer = row
            yBest = yAxis
        }
        return answer
    }

    func performAction(_ action: String) {
        switch action {
        case PageControl.next.rawValue:
            let pageNumbers = archivePageModel.archivePages[archiveItem.id]?.count ?? 1
            if archivePageModel.currentIndex < pageNumbers - 1 {
                withAnimation(.easeInOut) {
                    archivePageModel.currentIndex += 1
                }
            }
        case PageControl.previous.rawValue:
            if archivePageModel.currentIndex > 0 {
                withAnimation(.easeInOut) {
                    archivePageModel.currentIndex -= 1
                }
            }
        case PageControl.navigation.rawValue:
            archivePageModel.controlUiHidden.toggle()
        default:
            // This should not happen
            break
        }
    }

}
