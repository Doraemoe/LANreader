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

        let pageId: String
        let suffix: String
        let pageNumber: Int
        var loading: Bool = false
        var progress: Double = 0
        var errorMessage = ""
        var pageMode: PageMode
        let cached: Bool

        var id: String {
            "\(pageId)-\(suffix)"
        }

        let folder: URL?
        let path: URL?
        let pathLeft: URL?
        let pathRight: URL?

        init(archiveId: String, pageId: String, pageNumber: Int, pageMode: PageMode = .loading, cached: Bool = false) {
            self.pageId = pageId
            self.pageNumber = pageNumber
            self.pageMode = pageMode
            self.suffix = pageMode.rawValue
            self.cached = cached
            let imagePath = if cached {
                LANraragiService.cachePath
            } else {
                LANraragiService.downloadPath
            }
            self.folder = imagePath?.appendingPathComponent(archiveId, conformingTo: .folder)
            self.path = self.folder?
                .appendingPathComponent("\(pageNumber).heic", conformingTo: .heic)
            self.pathLeft = self.folder?
                .appendingPathComponent("\(pageNumber)-left.heic", conformingTo: .heic)
            self.pathRight = self.folder?
                .appendingPathComponent("\(pageNumber)-right.heic", conformingTo: .heic)
        }
    }

    enum Action: Equatable {
        case load(Bool)
        case setIsLoading(Bool)
        case subscribeToProgress(DownloadRequest)
        case cancelSubscribeImageProgress
        case setProgress(Double)
        case setImage(PageMode, Bool)
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

                let previousPageMode = state.pageMode

                if force {
                    state.pageMode = .loading
                } else if state.pageMode == .loading {
                    if state.splitImage && !state.fallback {
                        if state.piorityLeft &&
                            FileManager.default.fileExists(
                                atPath: state.pathLeft?.path(percentEncoded: false) ?? ""
                            ) {
                            state.pageMode = .left
                            return .send(.insertPage(.right))
                        } else if FileManager.default.fileExists(
                            atPath: state.pathRight?.path(percentEncoded: false) ?? ""
                        ) {
                            state.pageMode = .right
                            return .send(.insertPage(.left))
                        }
                    }
                    if FileManager.default.fileExists(atPath: state.path?.path(percentEncoded: false) ?? "") {
                        state.pageMode = .normal
                        return .none
                    }
                } else {
                    return .none
                }

                if state.pageMode == .loading {
                    if state.cached {
                        state.loading = false
                        return .send(.setError(String(localized: "archive.cache.page.load.failed")))
                    } else {
                        return .run { [state] send in
                            do {
                                let task = service.fetchArchivePage(page: state.pageId, pageNumber: state.pageNumber)
                                await send(.subscribeToProgress(task))
                                let imageUrl = try await task
                                    .serializingDownloadedFileURL()
                                    .value
                                await send(.cancelSubscribeImageProgress)

                                if !state.showOriginal {
                                    await send(.setProgress(2.0))
                                }
                                let splitted = imageService.resizeImage(
                                    imageUrl: imageUrl,
                                    destinationUrl: state.folder!,
                                    pageNumber: String(state.pageNumber),
                                    split: state.splitImage && !state.fallback,
                                    skip: state.showOriginal
                                )
                                await send(.setImage(previousPageMode, splitted))
                            } catch {
                                logger.error("failed to load image. \(error)")
                            }
                            await send(.setIsLoading(false))
                        }
                    }
                }
                state.loading = false
                return .none
            case let .setIsLoading(loading):
                state.loading = loading
                return .none
            case let .setProgress(progres):
                state.progress = progres
                return .none
            case let .setImage(previousPageMode, splitted):
                state.progress = 0
                state.loading = false
                if splitted {
                    if previousPageMode == .left || previousPageMode == .right {
                        state.pageMode = previousPageMode
                        return .none
                    }
                    if state.piorityLeft {
                        state.pageMode = .left
                        return .send(.insertPage(.right))
                    } else {
                        state.pageMode = .right
                        return .send(.insertPage(.left))
                    }
                } else {
                    state.pageMode = .normal
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

    // LazyHStack not clean up memory after item load and go off screen
    // Use this state to explicity release memory when page go off screen
    @State var visible = false

    var body: some View {
        // If not wrapped in ZStack, TabView will render ALL pages when initial load
        ZStack {
                if store.pageMode == .loading {
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
                } else {
                    if visible {
                        let contentPath = {
                            switch store.pageMode {
                            case .left:
                                return store.pathLeft
                            case .right:
                                return store.pathRight
                            default:
                                return store.path
                            }
                        }()

                        if let uiImage = UIImage(contentsOfFile: contentPath?.path(percentEncoded: false) ?? "") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .draggableAndZoomable(contentSize: geometrySize)
                        } else {
                            Image(systemName: "rectangle.slash")
                                .frame(height: geometrySize.height)
                        }
                    } else {
                        Color.clear
                    }
                }
        }
        .onAppear {
            visible = true
        }
        .onDisappear {
            visible = false
        }
    }
}

enum PageMode: String {
    case loading
    case left
    case right
    case normal
}
