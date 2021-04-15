//
// Created by Yifan Jin on 14/4/21.
// Copyright (c) 2021 Jin Yifan. All rights reserved.
//

import SwiftUI

struct ArchivePageV2: View {
    @AppStorage(SettingsKey.tapLeftKey) var tapLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.tapMiddleKey) var tapMiddle: String = PageControl.navigation.rawValue
    @AppStorage(SettingsKey.tapRightKey) var tapRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.verticalReader) var verticalReader: Bool = false

    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @StateObject private var archivePageModel = ArchivePageModelV2()

    @State private var verticalScrollTarget: Double?

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
                        ScrollView {
                            ScrollViewReader { reader in
                                LazyVStack {
                                    ForEach(0..<pages!.count) { index in
                                        PageImage(pageId: pages![index]).id(Double(index))
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: geometry.size.width)
                                    }
                                }
                                        .onChange(of: verticalScrollTarget) { target in
                                            if let target = target {
                                                verticalScrollTarget = nil
                                                reader.scrollTo(target, anchor: .top)
                                            }
                                        }
                            }
                        }
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
                                .opacity(0.0001)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: { performAction(tapMiddle) })
                    }
                } else {
                    if pages?.isEmpty == false {
                        TabView(selection: self.$archivePageModel.currentIndex) {
                            ForEach(0..<pages!.count) { index in
                                PageImage(pageId: pages![index]).tag(Double(index))
                                        .scaledToFit()
                                        .aspectRatio(contentMode: .fit)
                            }
                        }
                                .tabViewStyle(PageTabViewStyle())
                                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
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
                        archivePageModel.load(state: store.state)
                        extractArchive()
                    })
        }
    }

    private func extractArchive() {
        if archivePageModel.archivePages[archiveItem.id]?.isEmpty ?? true {
            store.dispatch(.page(action: .extractArchive(id: archiveItem.id)))
        }
    }

    private func getIntPart(_ number: Double) -> Int {
        Int(exactly: number.rounded()) ?? 0
    }

    func performAction(_ action: String) {
        switch action {
        case PageControl.next.rawValue:
            archivePageModel.currentIndex += archivePageModel.currentIndex
        case PageControl.previous.rawValue:
            archivePageModel.currentIndex -= archivePageModel.currentIndex
        case PageControl.navigation.rawValue:
            archivePageModel.controlUiHidden.toggle()
        default:
            // This should not happen
            break
        }
    }

}