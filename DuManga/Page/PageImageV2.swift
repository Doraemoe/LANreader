import ComposableArchitecture
import SwiftUI
import Logging

struct PageFeature: Reducer {
    private let logger = Logger(label: "PageFeature")

    struct State: Equatable, Identifiable {
        var id: String
        var image: ArchiveImage?
        var loading: Bool = false
        var errorMessage = ""
    }

    enum Action: Equatable {
        case load(String, Bool)
        case setImage(ArchiveImage?)
        case setError(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(id, force):
                guard !state.loading else {
                    return .none
                }
                state.loading = true

                if !force {
                    do {
                        state.image = try database.readArchiveImage(id)
                    } catch {
                        logger.error("failed to load image. id=\(id) \(error)")
                        return .send(.setError(error.localizedDescription))
                    }
                }
                if force || state.image == nil {
                    return .run { send in
                        do {
                            let imageUrl = try await service.fetchArchivePage(page: id)
                                .serializingDownloadedFileURL()
                                .value
                            var  pageImage = ArchiveImage(id: id, image: imageUrl.path, lastUpdate: Date())
                            do {
                                try database.saveArchiveImage(&pageImage)
                            } catch {
                                logger.error("failed to save page to db. pageId=\(id) \(error)")
                            }
                            await send(.setImage(pageImage))
                        } catch {
                            logger.error("failed to load image. \(error)")
                            await send(.setImage(nil))
                        }
                    }
                }
                return .none
            case let .setImage(image):
                state.loading = false
                state.image = image
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            }
        }
    }
}

struct PageImageV2: View {
    let store: StoreOf<PageFeature>

    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            Group {
                if let imageUrl = viewStore.image?.image {
                    if let uiImage = UIImage(contentsOfFile: imageUrl) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
//                            .frame(width: geometrySize.width)
//                            .draggableAndZoomable(contentSize: geometrySize)
                    } else {
                        Image(systemName: "rectangle.slash")
                    }
                } else {
                    Text("loading")
                        .onAppear {
                            viewStore.send(.load(viewStore.id, false))
                        }
                }
            }
        }

    }
}
