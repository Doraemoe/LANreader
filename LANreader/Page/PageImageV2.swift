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

        var image: Data?
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

        let path: URL?
        let pathLeft: URL?
        let pathRight: URL?

        init(archiveId: String, pageId: String, pageNumber: Int, pageMode: PageMode = .normal) {
            self.pageId = pageId
            self.pageNumber = pageNumber
            self.pageMode = pageMode
            self.suffix = pageMode.rawValue
            self.path = LANraragiService.downloadPath?
                .appendingPathComponent(archiveId, conformingTo: .folder)
                .appendingPathComponent("\(pageNumber)", conformingTo: .image)
            self.pathLeft = LANraragiService.downloadPath?
                .appendingPathComponent(archiveId, conformingTo: .folder)
                .appendingPathComponent("\(pageNumber)-left", conformingTo: .image)
            self.pathRight = LANraragiService.downloadPath?
                .appendingPathComponent(archiveId, conformingTo: .folder)
                .appendingPathComponent("\(pageNumber)-right", conformingTo: .image)
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
                } else {
                    switch state.pageMode {
                    case .normal:
                        if let path = state.path {
                            state.image = try? Data(contentsOf: path)
                        }
                    case .left:
                        if let path = state.pathLeft {
                            state.image = try? Data(contentsOf: path)
                        }
                    case .right:
                        if let path = state.pathRight {
                            state.image = try? Data(contentsOf: path)
                        }
                    }
                }

                if state.image == nil {
                    return .run { [state] send in
                        do {
                            let task = service.fetchArchivePage(page: state.pageId, pageNumber: state.pageNumber)
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
                    if let path = state.pathLeft {
                        try? leftImage!.write(to: path)
                    }
                    if let path = state.pathRight {
                        try? rightImage!.write(to: path)
                    }
                    if state.piorityLeft {
                        state.pageMode = .left
                        state.image = leftImage
                        return .send(.insertPage(.right))
                    } else {
                        state.pageMode = .right
                        state.image = rightImage
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
            if let imageData = store.image {
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
