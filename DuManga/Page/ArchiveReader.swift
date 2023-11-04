import ComposableArchitecture
import SwiftUI
import Logging

struct ArchiveReaderFeature: Reducer {
    private let logger = Logger(label: "ArchiveReaderFeature")

    struct State: Equatable {
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var archive: ArchiveItem
        var extracting = false
        var errorMessage = ""
    }

    enum Action: Equatable {
        case page(id: PageFeature.State.ID, action: PageFeature.Action)
        case extractArchive
        case finishExtracting([String])
        case setError(String)
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .extractArchive:
                state.extracting = true
                let id = state.archive.id
                return .run { send in
                    do {
                        let extractResponse = try await service.extractArchive(id: id).value
                        if extractResponse.pages.isEmpty {
                            logger.error("server returned empty pages. id=\(id)")
                            let errorMessage = NSLocalizedString("error.page.empty", comment: "empty content")
                            await send(.setError(errorMessage))
                        }
                        await send(.finishExtracting(extractResponse.pages))
                    } catch {
                        logger.error("failed to extract archive page. id=\(id) \(error)")
                        await send(.setError(error.localizedDescription))
                        await send(.finishExtracting([]))
                    }
                }
            case let .finishExtracting(pages):
                let pageState = pages.map { page in
                    let normalizedPage = String(page.dropFirst(2))
                    return PageFeature.State(id: normalizedPage)
                }
                state.pages.append(contentsOf: pageState)
                state.extracting = false
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            default:
                return .none
            }
        }
        .forEach(\.pages, action: /Action.page(id:action:)) {
            PageFeature()
        }
    }
}

struct ArchiveReader: View {

    let store: StoreOf<ArchiveReaderFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            GeometryReader { geometry in
                ZStack {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEachStore(
                                self.store.scope(state: \.pages, action: { .page(id: $0, action: $1) })
                            ) { pageStore in
                                PageImageV2(store: pageStore)
                                    .frame(width: geometry.size.width)
                                    .draggableAndZoomable(contentSize: geometry.size)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    if viewStore.extracting {
                        LoadingView(geometry: geometry)
                    }
                }

            }
            .navigationBarTitle(viewStore.archive.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                if viewStore.pages.isEmpty {
                    viewStore.send(.extractArchive)
                }
            }
        }
    }
}
