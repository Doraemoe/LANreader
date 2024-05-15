import SwiftUI
import ComposableArchitecture

@Reducer struct AutomaticPageFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage(SettingsKey.autoPageInterval)) var autoPageInterval = 5.0

        var showAutomaticPage: Bool = false
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case startAutoPage
        case cancelAutoPage
    }

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { _, action in
            switch action {
            default:
                return .none
            }
        }
    }
}

struct AutomaticPageConfig: View {
    @Bindable var store: StoreOf<AutomaticPageFeature>

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .foregroundColor(Color.black.opacity(0.5))
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .frame(
                            width: max(geometry.size.width * 0.4, 280),
                            height: max(geometry.size.height * 0.2, 250),
                            alignment: .center
                        )
                        .overlay(
                            VStack {
                                Text("settings.read.auto.page.interval")
                                    .padding()
                                HStack {
                                    Slider(
                                        value: $store.autoPageInterval,
                                        in: 0.0...20.0,
                                        step: 1
                                    )
                                    Text("\(store.autoPageInterval, specifier: "%.0f")s")
                                }
                                .padding(.horizontal)
                                Text("settings.read.auto.page.interval.cancel")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding()
                                HStack {
                                    Button(role: .cancel, action: {
                                        store.send(.cancelAutoPage)
                                    }, label: {
                                        Text("cancel")
                                    })
                                    .padding()
                                    Button(action: {
                                        store.send(.startAutoPage)
                                    }) {
                                        Text("play")
                                    }
                                    .padding()
                                }
                            }
                        )

                )
        }
    }
}
