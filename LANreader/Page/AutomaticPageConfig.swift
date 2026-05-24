import SwiftUI
import ComposableArchitecture

@Reducer public struct AutomaticPageFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        @Shared(.appStorage(SettingsKey.autoPageInterval)) var autoPageInterval = 5.0

        var showAutomaticPage: Bool = false
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case startAutoPage
        case cancelAutoPage
    }

    public var body: some Reducer<State, Action> {
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
            ZStack {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Image(systemName: "timer")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .systemBlue))
                        .frame(width: 54, height: 54)
                        .background(Color(uiColor: .secondarySystemBackground).opacity(0.86), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }

                    VStack(spacing: 8) {
                        Text("settings.read.auto.page.interval")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Text("settings.read.auto.page.interval.cancel")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    intervalSlider

                    HStack(spacing: 12) {
                        Button(role: .cancel) {
                            store.send(.cancelAutoPage)
                        } label: {
                            Label("cancel", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.send(.startAutoPage)
                        } label: {
                            Label("play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                    .labelStyle(.titleAndIcon)
                }
                .padding(24)
                .frame(width: dialogWidth(for: geometry.size))
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.24), radius: 26, x: 0, y: 16)
                .padding(.horizontal, 20)
            }
        }
        .transition(.opacity)
    }

    private var intervalSlider: some View {
        HStack(spacing: 14) {
            Slider(
                value: Binding(store.$autoPageInterval),
                in: 1.0...20.0,
                step: 1
            )
            .tint(Color(uiColor: .systemBlue))

            Text("\(store.autoPageInterval, specifier: "%.0f")s")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 58, height: 40)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .padding(.horizontal, 4)
    }

    private func dialogWidth(for size: CGSize) -> CGFloat {
        min(max(size.width - 40, 300), 430)
    }
}
