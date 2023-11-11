import ComposableArchitecture
import SwiftUI
import Logging

struct PageFeature: Reducer {
    private let logger = Logger(label: "PageFeature")

    struct State: Equatable, Identifiable {
        var id: Int
        var pageId: String
        var image: ArchiveImage?
        var loading: Bool = false
        var progress: Double = 0
        var errorMessage = ""
    }

    enum Action: Equatable {
        case load(Bool)
        case setProgress(Double)
        case setImage(ArchiveImage?)
        case setError(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                guard !state.loading else {
                    return .none
                }
                state.loading = true

                if !force {
                    do {
                        state.image = try database.readArchiveImage(state.pageId)
                    } catch {
                        logger.error("failed to load image. id=\(state.pageId) \(error)")
                        return .send(.setError(error.localizedDescription))
                    }
                } else {
                    state.image = nil
                }
                if state.image == nil {
                    return .run { [id = state.pageId] send in
                        do {
                            let task = service.fetchArchivePage(page: id)

                            let progressTask = Task(priority: .utility) {
                                var step: Double = 0.0
                                for await progress in task.downloadProgress() {
                                    let percentage = progress.fractionCompleted
                                    if percentage > step {
                                        await send(.setProgress(percentage))
                                        step =  percentage + 0.1
                                    }
                                }
                            }

                            let imageUrl = try await task
                                .serializingDownloadedFileURL()
                                .value
                            progressTask.cancel()
                            var  pageImage = ArchiveImage(
                                id: id, image: imageUrl.path(percentEncoded: false), lastUpdate: Date()
                            )
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
            case let .setProgress(progres):
                state.progress = progres
                return .none
            case let .setImage(image):
                state.loading = false
                state.image = image
                return .none
            case let .setError(message):
                state.loading = false
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
                    } else {
                        Image(systemName: "rectangle.slash")
                    }
                } else {
                    ProgressView(
                        value: viewStore.progress > 1 ? 1 : viewStore.progress,
                        total: 1
                    ) {
                        Text("loading")
                    } currentValueLabel: {
                        viewStore.progress > 1 ?
                        Text("downsampling") :
                        Text(String(format: "%.2f%%", viewStore.progress * 100))
                    }
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 20)
                    .tint(.primary)
                    .onAppear {
                        viewStore.send(.load(false))
                    }
                }
            }
        }

    }
}
