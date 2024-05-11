import ComposableArchitecture
import Alamofire
import SwiftUI
import Logging

@Reducer struct PageFeature {
    private let logger = Logger(label: "PageFeature")

    @ObservableState
    struct State: Equatable, Identifiable {
        @SharedReader(.appStorage(SettingsKey.showOriginal)) var showOriginal = false
        @SharedReader(.appStorage(SettingsKey.fallbackReader)) var fallback = false
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.splitPiorityLeft)) var piorityLeft = false

        @Shared var image: Data?
        @Shared var imageLeft: Data?
        @Shared var imageRight: Data?

        let pageId: String
        let suffix: String
        let pageNumber: Int
        var loading: Bool = false
        var progress: Double = 0
        var errorMessage = ""
        var pageMode: PageMode = .normal

        var id: String {
            "\(pageId)-\(suffix)"
        }

        init(archiveId: String, pageId: String, pageNumber: Int, pageMode: PageMode = .normal) {
            self.pageId = pageId
            self.pageNumber = pageNumber
            self.pageMode = pageMode
            self.suffix = pageMode.rawValue

            self._image = Shared(
                wrappedValue: nil,
                .fileStorage(
                    LANraragiService.downloadPath!
                        .appendingPathComponent(archiveId, conformingTo: .folder)
                        .appendingPathComponent(pageId, conformingTo: .image)
                )
            )
            self._imageLeft = Shared(
                wrappedValue: nil,
                .fileStorage(
                    LANraragiService.downloadPath!
                        .appendingPathComponent(archiveId, conformingTo: .folder)
                        .appendingPathComponent("\(pageId)-left", conformingTo: .image)
                )
            )
            self._imageRight = Shared(
                wrappedValue: nil,
                .fileStorage(
                    LANraragiService.downloadPath!
                        .appendingPathComponent(archiveId, conformingTo: .folder)
                        .appendingPathComponent("\(pageId)-right", conformingTo: .image)
                )
            )
        }
    }

    enum Action: Equatable {
        case load(Bool)
        case subscribeToProgress(DownloadRequest)
        case cancelSubscribeImageProgress
        case setProgress(Double)
        case setImage(Data, Data?, Data?)
        case setError(String)
        case insertPage(PageMode)
    }

    @Dependency(\.lanraragiService) var service
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

                if force {
                    state.image = nil
                    state.imageLeft = nil
                    state.imageRight = nil
                }

                let imageToRefresh = switch state.pageMode {
                case .normal:
                    state.image
                case .left:
                    state.imageLeft
                case .right:
                    state.imageRight
                }

                if imageToRefresh == nil {
                    return .run { [state] send in
                        do {
                            let task = service.fetchArchivePage(page: state.pageId)
                            await send(.subscribeToProgress(task))
                            let imageData = try await task
                                .serializingData()
                                .value
                            await send(.cancelSubscribeImageProgress)

                            if !state.showOriginal {
                                await send(.setProgress(2.0))
                            }
                            let (processedImage, leftImage, rightImage) = imageService.resizeImage(
                                data: imageData,
                                split: state.splitImage && !state.fallback,
                                skip: state.showOriginal
                            )
                            await send(.setImage(processedImage, leftImage, rightImage))
                        } catch {
                            logger.error("failed to load image. \(error)")
                        }
                    }
                }
                return .none
            case let .setProgress(progres):
                state.progress = progres
                return .none
            case let .setImage(processedImage, leftImage, rightImage):
                state.progress = 0
                state.loading = false
                if leftImage != nil && rightImage != nil {
                    if state.piorityLeft {
                        state.imageLeft = leftImage
                        state.imageRight = rightImage
                        state.pageMode = .left
                        return .send(.insertPage(.right))
                    } else {
                        state.imageRight = rightImage
                        state.imageLeft = leftImage
                        state.pageMode = .right
                        return .send(.insertPage(.left))
                    }
                } else {
                    state.image = processedImage
                }
                return .none
            case let .setError(message):
                state.loading = false
                state.errorMessage = message
                return .none
            case .insertPage:
                return .none
            }
        }
    }
}

struct PageImageV2: View {
    let store: StoreOf<PageFeature>
    let geometrySize: CGSize

    var body: some View {
        // If not wrapped in ZStack, TabView will render ALL pages when initial load
        ZStack {
            let imageToDisplay = switch store.pageMode {
            case .normal:
                store.image
            case .left:
                store.imageLeft
            case .right:
                store.imageRight
            }
            if let imageData = imageToDisplay {
                if let uiImage = UIImage(data: imageData) {
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
                    value: store.progress > 1 ? 1 : store.progress,
                    total: 1
                ) {
                    Text("loading")
                } currentValueLabel: {
                    store.progress > 1 ?
                    Text("downsampling") :
                    Text(String(format: "%.2f%%", store.progress * 100))
                }
                .progressViewStyle(.linear)
                .frame(height: geometrySize.height)
                .padding(.horizontal, 20)
                .tint(.primary)
                .task {
                    store.send(.load(false))
                }
            }
        }
    }
}

enum PageMode: String {
    case left
    case right
    case normal
}
