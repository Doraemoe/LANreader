// Created 29/8/20
import ComposableArchitecture
import SwiftUI

@Reducer struct ReadSettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage(SettingsKey.tapLeftKey)) var tapLeft = PageControl.next.rawValue
        @Shared(.appStorage(SettingsKey.tapMiddleKey)) var tapMiddle = PageControl.navigation.rawValue
        @Shared(.appStorage(SettingsKey.tapRightKey)) var tapRight = PageControl.previous.rawValue
        @Shared(.appStorage(SettingsKey.readDirection)) var readDirection = ReadDirection.leftRight.rawValue
        @Shared(.appStorage(SettingsKey.showOriginal)) var showOriginal = false
        @Shared(.appStorage(SettingsKey.fallbackReader)) var fallbackReader = false
    }
    enum Action: BindableAction {
        case binding(BindingAction<State>)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { _, action in
            switch action {
            default:
                return .none
            }
        }
    }
}

struct ReadSettings: View {
    @Bindable var store: StoreOf<ReadSettingsFeature>

    var body: some View {
        Picker("settings.read.direction", selection: self.$store.readDirection) {
            Text("settings.read.direction.leftRight").tag(ReadDirection.leftRight.rawValue)
            Text("settings.read.direction.rightLeft").tag(ReadDirection.rightLeft.rawValue)
            Text("settings.read.direction.upDown").tag(ReadDirection.upDown.rawValue)
        }
        .padding()
        if store.readDirection != ReadDirection.upDown.rawValue {
            Picker("settings.read.tap.left", selection: self.$store.tapLeft) {
                pageControlSelectionView
            }
            .padding()
        }
        if store.readDirection != ReadDirection.upDown.rawValue {
            Picker("settings.read.tap.middle", selection: self.$store.tapMiddle) {
                pageControlSelectionView
            }
            .padding()
            Picker("settings.read.tap.right", selection: self.$store.tapRight) {
                pageControlSelectionView
            }
            .padding()
            Toggle(isOn: self.$store.fallbackReader) {
                Text("settings.read.fallback")
            }
            .padding()
        }
        Toggle(isOn: self.$store.showOriginal) {
            Text("settings.read.image.showOriginal")
        }
        .padding()
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
