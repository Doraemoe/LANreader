// Created 1/9/20
import ComposableArchitecture
import SwiftUI

@Reducer struct ViewSettingsFeature {
    struct State: Equatable {
        @PresentationState var destination: Destination.State?

        @BindingState var searchSortSelected: String
        @BindingState var searchSort: String

        init() {
            let searchSort = UserDefaults.standard.string(forKey: SettingsKey.searchSort) ?? "date_added"
            if let currentSort = SearchSort.init(rawValue: searchSort) {
                self.searchSortSelected = currentSort.rawValue
            } else {
                self.searchSortSelected = SearchSort.custom.rawValue
            }
            self.searchSort = searchSort
        }
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case destination(PresentationAction<Destination.Action>)

        case searchSortChanged(String)
        case submitCustomSearchSort
        case showLockScreen(Bool)
    }

    @Dependency(\.userDefaultService) var userDefault

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case let .showLockScreen(isEnable):
                state.destination = .lockScreen(
                    LockScreenFeature.State(lockState: isEnable ? .new : .remove)
                )
                return .none
            case let .searchSortChanged(oldSort):
                if state.searchSortSelected != SearchSort.custom.rawValue {
                    userDefault.setSearchSort(searchSort: state.searchSortSelected)
                } else {
                    state.searchSort = oldSort
                }
                return .none
            case .submitCustomSearchSort:
                userDefault.setSearchSort(searchSort: state.searchSort)
                return .none
            default:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) {
          Destination()
        }
    }

    @Reducer public struct Destination {
      public enum State: Equatable {
        case lockScreen(LockScreenFeature.State)
      }

        public enum Action: Equatable {
        case lockScreen(LockScreenFeature.Action)
      }

      public var body: some Reducer<State, Action> {
        Scope(state: \.lockScreen, action: \.lockScreen) {
            LockScreenFeature()
        }
      }
    }
}

struct ViewSettings: View {
    @AppStorage(SettingsKey.searchSortOrder) var searchSortOrder: String = SearchSortOrder.asc.rawValue
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false
    @AppStorage(SettingsKey.enablePasscode) var enablePasscode: Bool = false
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""

    let store: StoreOf<ViewSettingsFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            List {
                Picker("settings.archive.list.order", selection: viewStore.$searchSortSelected) {
                    Text("settings.archive.list.order.dateAdded").tag(SearchSort.dateAdded.rawValue)
                    Text("settings.archive.list.order.name").tag(SearchSort.name.rawValue)
                    Text("settings.archive.list.order.artist").tag(SearchSort.artist.rawValue)
                    Text("settings.archive.list.order.group").tag(SearchSort.group.rawValue)
                    Text("settings.archive.list.order.event").tag(SearchSort.event.rawValue)
                    Text("settings.archive.list.order.series").tag(SearchSort.series.rawValue)
                    Text("settings.archive.list.order.character").tag(SearchSort.character.rawValue)
                    Text("settings.archive.list.order.parody").tag(SearchSort.parody.rawValue)
                    Text("settings.archive.list.order.custom").tag(SearchSort.custom.rawValue)
                }
                .onChange(of: viewStore.searchSortSelected, { oldSort, newSort in
                    if oldSort != newSort {
                        viewStore.send(.searchSortChanged(oldSort))
                    }
                })
                .padding()
                if viewStore.searchSortSelected == SearchSort.custom.rawValue {
                    LabeledContent {
                        TextField("settings.archive.list.order.custom.title", text: viewStore.$searchSort)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                viewStore.send(.submitCustomSearchSort)
                            }
                    } label: {
                        Text("settings.archive.list.order.custom.title")
                    }
                    .padding()
                }
                Picker("settings.archive.list.order.sort", selection: $searchSortOrder) {
                    Text("settings.archive.list.order.sort.asc").tag(SearchSortOrder.asc.rawValue)
                    Text("settings.archive.list.order.sort.desc").tag(SearchSortOrder.desc.rawValue)
                }
                .padding()
                Toggle(isOn: self.$hideRead, label: {
                    Text("settings.view.hideRead")
                })
                .padding()
                Toggle(isOn: self.$blurInterfaceWhenInactive, label: {
                    Text("settings.view.blur.inactive")
                })
                .padding()
                Toggle(isOn: self.$enablePasscode, label: {
                    Text("settings.view.passcode")
                })
                .padding()
            }
            .onAppear {
                // Correct invalid passcode status
                if enablePasscode && storedPasscode.isEmpty {
                    enablePasscode = false
                } else if !enablePasscode && !storedPasscode.isEmpty {
                    enablePasscode = true
                }
            }
            .onChange(of: enablePasscode) { oldPasscode, newEnable in
                if oldPasscode && storedPasscode.isEmpty {
                    // heppens when correct invalid passcode status
                } else if !oldPasscode && !storedPasscode.isEmpty {
                    // heppens when correct invalid passcode status
                } else if viewStore.destination == nil {
                    viewStore.send(.showLockScreen(newEnable))
                }
            }
            .fullScreenCover(
                store: self.store.scope(state: \.$destination.lockScreen, action: \.destination.lockScreen)
            ) { store in
                LockScreen(store: store)
            }
        }
    }
}
