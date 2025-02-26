// Created 29/8/20
import ComposableArchitecture
import SwiftUI

@Reducer public struct ReadSettingsFeature {
    @ObservableState
    public struct State: Equatable {
        @Shared(.appStorage(SettingsKey.tapLeftKey)) var tapLeft = PageControl.next.rawValue
        @Shared(.appStorage(SettingsKey.tapMiddleKey)) var tapMiddle = PageControl.navigation.rawValue
        @Shared(.appStorage(SettingsKey.tapRightKey)) var tapRight = PageControl.previous.rawValue
        @Shared(.appStorage(SettingsKey.readDirection)) var readDirection = ReadDirection.leftRight.rawValue
        @Shared(.appStorage(SettingsKey.showOriginal)) var showOriginal = false
        @Shared(.appStorage(SettingsKey.splitWideImage)) var splitWideImage = false
        @Shared(.appStorage(SettingsKey.splitPiorityLeft)) var splitPiorityLeft = false
        @Shared(.appStorage(SettingsKey.doublePageLayout)) var doublePageLayout = false
    }
    public enum Action: BindableAction {
        case binding(BindingAction<State>)
    }

    public var body: some ReducerOf<Self> {
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
        }
        if store.readDirection != ReadDirection.upDown.rawValue {
            Toggle(isOn: self.$store.doublePageLayout) {
                Text("settings.read.double.page")
            }
            .padding()
        }
        Toggle(isOn: self.$store.splitWideImage) {
            Text("settings.read.split.page")
        }
        .padding()
        if self.store.splitWideImage {
            Toggle(isOn: self.$store.splitPiorityLeft) {
                Text("settings.read.split.page.priority.left")
            }
            .padding()
        }
    }

    var pageControlSelectionView: some View = Group {
        Text("settings.nextPage").tag(PageControl.next.rawValue)
        Text("settings.previousPage").tag(PageControl.previous.rawValue)
        Text("settings.navigation").tag(PageControl.navigation.rawValue)
    }
}
