import ComposableArchitecture
import OrderedCollections
import SwiftUI

struct ArchiveListFeature: Reducer {
    struct State: Equatable {
        var archives = [ArchiveItem]()
        var loading: Bool = false
        var total: Int = 0
    }

    enum Action: Equatable {
        case appendArchives(String)
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .appendArchives:
                return .none
            }
        }
    }

}

struct ArchiveListV2: View {
    let store: StoreOf<ArchiveListFeature>

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack {
                    LazyVGrid(columns: columns) {
                        ForEach(viewStore.archives) { (item: ArchiveItem) in
                            ArchiveGrid(archiveItem: item)
                                .onAppear {
                                    if item.id == viewStore.archives.last?.id && viewStore.archives.count < viewStore.total {
                                        viewStore.send(.appendArchives(String(viewStore.archives.count)))
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                    if viewStore.loading {
                        ProgressView("loading")
                    }
                }
            }
        }

    }

//    private func sortPicker() -> some View {
//        Group {
//            if archives.isEmpty {
//                EmptyView()
//            } else {
//                HStack {
//                    Picker("settings.archive.list.order", selection: self.$archiveListOrder) {
//                        Group {
//                            Text("settings.archive.list.order.name").tag(ArchiveListOrder.name.rawValue)
//                            Text("settings.archive.list.order.dateAdded").tag(ArchiveListOrder.dateAdded.rawValue)
//                            Text("settings.archive.list.order.random").tag(ArchiveListOrder.random.rawValue)
//                        }
//                    }
//                    .pickerStyle(.segmented)
//                    Text("settings.view.hideRead")
//                    Toggle("", isOn: self.$hideRead)
//                        .labelsHidden()
//                }
//                .padding()
//            }
//        }
//    }
}

// #Preview {
//    ArchiveListV2(store: Store(initialState: ArchiveListFeature.State(category: "", filter: ""), reducer: {
//        ArchiveListFeature()
//    }))
// }
