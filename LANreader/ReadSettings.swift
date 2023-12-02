// Created 29/8/20
import ComposableArchitecture
import SwiftUI

struct ReadSettings: View {
    @AppStorage(SettingsKey.tapLeftKey) var tapLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.tapMiddleKey) var tapMiddle: String = PageControl.navigation.rawValue
    @AppStorage(SettingsKey.tapRightKey) var tapRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.readDirection) var readDirection: String = ReadDirection.leftRight.rawValue
    @AppStorage(SettingsKey.compressImageThreshold) var compressImageThreshold: CompressThreshold = .never
    @AppStorage(SettingsKey.showOriginal) var showOriginal: Bool = false
    @AppStorage(SettingsKey.fallbackReader) var fallbackReader: Bool = false

    var body: some View {
        return List {
            Picker("settings.read.direction", selection: self.$readDirection) {
                Text("settings.read.direction.leftRight").tag(ReadDirection.leftRight.rawValue)
                Text("settings.read.direction.rightLeft").tag(ReadDirection.rightLeft.rawValue)
                Text("settings.read.direction.upDown").tag(ReadDirection.upDown.rawValue)
            }
                    .padding()
            if readDirection != ReadDirection.upDown.rawValue {
                Picker("settings.read.tap.left", selection: self.$tapLeft) {
                    pageControlSelectionView
                }
                        .padding()
            }
            if readDirection != ReadDirection.upDown.rawValue {
                Picker("settings.read.tap.middle", selection: self.$tapMiddle) {
                    pageControlSelectionView
                }
                        .padding()
                Picker("settings.read.tap.right", selection: self.$tapRight) {
                    pageControlSelectionView
                }
                        .padding()
                Toggle(isOn: self.$fallbackReader) {
                    Text("settings.read.fallback")
                }
                .padding()
            }
            Toggle(isOn: self.$showOriginal) {
                Text("settings.read.image.showOriginal")
            }
            .padding()
        }
    }

    var pageControlSelectionView: some View = Group {
        Text("settings.nextPage").tag(PageControl.next.rawValue)
        Text("settings.previousPage").tag(PageControl.previous.rawValue)
        Text("settings.navigation").tag(PageControl.navigation.rawValue)
    }

    var compressSelectionView: some View = Group {
        Text("settings.read.image.compress.never").tag(CompressThreshold.never)
        Text("settings.read.image.compress.one").tag(CompressThreshold.one)
        Text("settings.read.image.compress.two").tag(CompressThreshold.two)
        Text("settings.read.image.compress.three").tag(CompressThreshold.three)
        Text("settings.read.image.compress.four").tag(CompressThreshold.four)
    }

}
