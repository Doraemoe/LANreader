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
    @AppStorage(SettingsKey.readDirection) var readDirection: String = ReadDirection.leftRight.rawValue
    @AppStorage(SettingsKey.compressImageThreshold) var compressThreshold: CompressThreshold = .never

    @Environment(\.presentationMode) var presentationMode

    @StateObject private var archivePageModel = ArchivePageModelV2()

    @State private var verticalScrollTarget: Int?

    private let store = AppStore.shared

    let archiveItem: ArchiveItem
    let startFromBeginning: Bool

    init(archiveItem: ArchiveItem, startFromBeginning: Bool = false) {
        self.archiveItem = archiveItem
        self.startFromBeginning = startFromBeginning
    }

    var body: some View {
        return GeometryReader { geometry in
            ZStack {
                if readDirection == ReadDirection.upDown.rawValue {
                    vReader(geometry: geometry)
                } else {
                    hReader(geometry: geometry)
                }
                // SwiftUI build in bottom tool bar only support single line height
                if !archivePageModel.controlUiHidden {
                    VStack {
                        Spacer()
                        bottomToolbar(pages: archivePageModel.pages)
                    }
                }
                if archivePageModel.loading {
                    LoadingView(geometry: geometry)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ArchiveDetails(item: archiveItem)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .navigationBarTitle(archiveItem.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(archivePageModel.controlUiHidden ? .hidden : .visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .task {
                if archivePageModel.pages.isEmpty {
                    await archivePageModel.extractArchive(id: archiveItem.id)
                }
            }
            .onAppear(perform: {
                archivePageModel.load(
                    progress: archiveItem.progress > 0 ? archiveItem.progress - 1 : 0,
                    startFromBeginning: startFromBeginning
                )
                archivePageModel.addToHistory(id: archiveItem.id)
            })
            .onChange(of: archivePageModel.deletedArchiveId, perform: { deletedArchiveId in
                if archiveItem.id == deletedArchiveId {
                    store.dispatch(.trigger(action: .archiveDeleteAction(id: "")))
                    presentationMode.wrappedValue.dismiss()
                }
            })
            .onChange(of: archivePageModel.errorMessage) { errorMessage in
                if !errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("error", comment: "error"),
                        subtitle: errorMessage,
                        style: .danger
                    )
                    banner.show()
                    archivePageModel.controlUiHidden = false
                }
            }
            .onChange(of: archivePageModel.currentIndex) { index in
                archivePageModel.prefetchImages()
                archivePageModel.sliderIndex = Double(archivePageModel.currentIndex)
                Task {
                    await onIndexChange(index: index)
                }

            }
            .onChange(of: archivePageModel.pages) { [pages = archivePageModel.pages] newPages in
                if pages.isEmpty && !newPages.isEmpty {
                    archivePageModel.prefetchImages()
                }
            }
        }
    }

    private func vReader(geometry: GeometryProxy) -> some View {
        ZStack {
            if archivePageModel.pages.isEmpty {
                // This is to make sure when onAppear called on ScrollView there is page to scroll to
                Color.clear
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack {
                            ForEach(0..<archivePageModel.pages.count, id: \.self) { index in
                                PageImage(id: archivePageModel.pages[index], geometrySize: geometry.size)
                                    .id(index)
                                    .anchorPreference(key: AnchorsKey.self, value: .center) {
                                        [index: $0]
                                    }
                                    .queryObservation(.onRender)
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

    private func hReader(geometry: GeometryProxy) -> some View {
        ZStack {
            if archivePageModel.pages.isEmpty == false {
                TabView(selection: self.$archivePageModel.currentIndex) {
                    ForEach(pageOrder(totalPage: archivePageModel.pages.count), id: \.self) { index in
                        PageImage(id: archivePageModel.pages[index], geometrySize: geometry.size).tag(index)
                            .queryObservation(.onRender)
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
                Color.clear
            }
        }
    }

    private func pageOrder(totalPage: Int) -> [Int] {
        if readDirection == ReadDirection.rightLeft.rawValue {
            return (0..<totalPage).reversed()
        } else {
            return Array(0..<totalPage)
        }
    }

    // swiftlint:disable function_body_length
    private func bottomToolbar(pages: [String]) -> some View {
        let flip = readDirection == ReadDirection.rightLeft.rawValue ? -1 : 1
        return Grid {
            GridRow {
                Button(action: {
                    store.dispatch(
                        .trigger(action: .pageRefreshAction(
                            id: archivePageModel.pages[archivePageModel.currentIndex])
                        )
                    )
                }, label: {
                    Image(systemName: "arrow.clockwise")
                })
                Text(String(format: "%d/%d",
                            archivePageModel.currentIndex + 1,
                            pages.count))
                .bold()
                Button(action: {
                    Task {
                        let result = await archivePageModel.setCurrentPageAsThumbnail(id: archiveItem.id)
                        if result.isEmpty {
                            let banner = NotificationBanner(
                                title: NSLocalizedString("success", comment: "error"),
                                subtitle: NSLocalizedString(
                                    "archive.thumbnail.set", comment: "set thumbnail success"
                                ),
                                style: .success
                            )
                            banner.show()
                        } else {
                            let banner = NotificationBanner(
                                title: NSLocalizedString("error", comment: "error"),
                                subtitle: result,
                                style: .danger
                            )
                            banner.show()
                        }
                    }
                }, label: {
                    Text("archive.thumbnail.current")
                })
            }
            GridRow {
                Slider(
                    value: self.$archivePageModel.sliderIndex,
                    in: 0...Double(pages.count < 1 ? 1 : pages.count - 1),
                    step: 1
                ) { onSlider in
                    if !onSlider {
                        archivePageModel.currentIndex = archivePageModel.sliderIndex.int
                        verticalScrollTarget = archivePageModel.sliderIndex.int
                    }
                }
                .scaleEffect(CGSize(width: flip, height: 1), anchor: .center)
                .padding(.horizontal)
                .gridCellColumns(3)
            }
        }
        .padding()
        .background(.thinMaterial)
    }
    // swiftlint:enable function_body_length

    private func onIndexChange(index: Int) async {
        await store.dispatch(updateReadProgress(
            id: archiveItem.id, progress: index + 1))
        if index == archiveItem.pagecount - 1 {
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
            let pageNumbers = archivePageModel.pages.count
            if archivePageModel.currentIndex < pageNumbers - 1 {
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
