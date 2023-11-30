import ComposableArchitecture
import Alamofire
import SwiftUI
import Logging

@Reducer struct PageFeature {
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
        case subscribeToProgress(DownloadRequest)
        case cancelSubscribeImageProgress
        case setProgress(Double)
        case setImage(ArchiveImage?)
        case setError(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.userDefaultService) var userDefault
    @Dependency(\.imageService) var imageService

    enum CancelId { case imageProgress }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .subscribeToProgress(progress):
                return .run(priority: .utility) { send in
                    var step: Double = 0.0
                    for await progress in progress.downloadProgress() {
                        let percentage = progress.fractionCompleted
                        if percentage > step {
                            await send(.setProgress(percentage))
                            step =  percentage + 0.1
                        }
                    }
                }
                .cancellable(id: CancelId.imageProgress)
            case .cancelSubscribeImageProgress:
                return .cancel(id: CancelId.imageProgress)
            case let .load(force):
                guard !state.loading || force else {
                    return .none
                }
                state.loading = true

                if !force {
                    do {
                        state.image = try database.readArchiveImage(state.pageId)
                    } catch {
                        logger.error("failed to load image. id=\(state.pageId) \(error)")
                    }
                } else {
                    state.image = nil
                }
                if state.image == nil {
                    return .run { [id = state.pageId] send in
                        do {
                            let task = service.fetchArchivePage(page: id)
                            await send(.subscribeToProgress(task))
                            let imageUrl = try await task
                                .serializingDownloadedFileURL()
                                .value
                            await send(.cancelSubscribeImageProgress)

                            if !userDefault.showOriginal {
                                await send(.setProgress(2.0))
                                imageService.resizeImage(url: imageUrl)
                            }

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
                state.progress = 0
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
    let geometrySize: CGSize

    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            // If not wrapped in ZStack, TabView will render ALL pages when initial load
            ZStack {
                if let imageUrl = viewStore.image?.image {
                    if let uiImage = UIImage(contentsOfFile: imageUrl) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .draggableAndZoomable(contentSize: geometrySize)
                    } else {
                        Image(systemName: "rectangle.slash")
                            .frame(height: geometrySize.height)
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
                    .frame(height: geometrySize.height)
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
