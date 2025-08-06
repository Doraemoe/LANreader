import ComposableArchitecture
import Alamofire
import SwiftUI
import Logging

@Reducer public struct PageFeature {
    private let logger = Logger(label: "PageFeature")

    @ObservableState
    public struct State: Equatable, Identifiable {
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.splitPiorityLeft)) var piorityLeft = false
        @SharedReader(.appStorage(SettingsKey.translationEnabled)) var translationEnabled = false

        let pageId: String
        let suffix: String
        let pageNumber: Int
        var loading: Bool = false
        var progress: Double = 0
        var errorMessage = ""
        var pageMode: PageMode
        let cached: Bool
        var imageLoaded = false
        var translationStatus = ""

        public var id: String {
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

    public enum Action: Equatable {
        case load(Bool)
        case setIsLoading(Bool)
        case subscribeToProgress(DownloadRequest)
        case cancelSubscribeImageProgress
        case setProgress(Double)
        case setImage(PageMode, Bool)
        case setError(String)
        case insertPage(PageMode)
        case setTranslationStatus(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService
    @Dependency(\.translatorService) var translatorService

    public enum CancelId { case imageProgress }

    public var body: some ReducerOf<Self> {
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
                state.errorMessage = ""
                state.imageLoaded = false

                let previousPageMode = state.pageMode

                if force {
                    state.pageMode = .loading
                } else if state.pageMode == .loading {
                    if state.splitImage {
                        if state.piorityLeft &&
                            FileManager.default.fileExists(
                                atPath: state.pathLeft?.path(percentEncoded: false) ?? ""
                            ) {
                            state.pageMode = .left
                            state.imageLoaded = true
                            return .send(.insertPage(.right))
                        } else if FileManager.default.fileExists(
                            atPath: state.pathRight?.path(percentEncoded: false) ?? ""
                        ) {
                            state.pageMode = .right
                            state.imageLoaded = true
                            return .send(.insertPage(.left))
                        }
                    }
                    if FileManager.default.fileExists(atPath: state.path?.path(percentEncoded: false) ?? "") {
                        state.pageMode = .normal
                        state.imageLoaded = true
                        return .none
                    }
                } else {
                    state.loading = false
                    state.imageLoaded = true
                    return .none
                }

                if state.pageMode == .loading {
                    if state.cached {
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

                                var translated: Data?
                                if state.translationEnabled {
                                    await send(.setProgress(2.0))

                                    guard let request = translatorService.translatePage(original: imageUrl) else {
                                        await send(
                                            .setError(
                                                String(localized: "archive.page.translate.request.failed")
                                            )
                                        )
                                        return
                                    }

                                    let handler = TranslationStreamHandler()
                                    let statusStream = handler.processStreamResponse(request)
                                    var lastCode = ""
                                    for try await status in statusStream {
                                        switch status {
                                        case .progress(let code):
                                            if code != lastCode {
                                                let translationString = String(
                                                    localized: "archive.page.translate.progress"
                                                )
                                                let progressString = handler.handleProgressCode(code: code)
                                                lastCode = code
                                                await send(
                                                    .setTranslationStatus("\(translationString) \(progressString)")
                                                )
                                            }
                                        case .pending(let queuePosition):
                                            if let position = queuePosition {
                                                let queueString = String(localized: "archive.page.translate.queue")
                                                await send(.setTranslationStatus("\(queueString) \(position)"))
                                            } else {
                                                let pendingString = String(localized: "archive.page.translate.pending")
                                                await send(.setTranslationStatus(pendingString))
                                            }
                                        case .error(let message):
                                            await send(.setError(message))
                                        case .completed(let data):
                                            translated = data
                                        }
                                    }
                                }

                                let splitted = imageService.resizeImage(
                                    imageUrl: imageUrl,
                                    imageData: translated,
                                    destinationUrl: state.folder!,
                                    pageNumber: String(state.pageNumber),
                                    split: state.splitImage
                                )
                                await send(.setImage(previousPageMode, splitted))
                            } catch {
                                logger.error("failed to load image. \(error)")
                                await send(.setError(error.localizedDescription))
                            }
                        }
                    }
                }
                state.loading = false
                state.imageLoaded = true
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
                state.imageLoaded = true
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
                state.imageLoaded = true
                state.errorMessage = message
                return .none
            case .insertPage:
                return .none
            case let .setTranslationStatus(status):
                state.translationStatus = status
                return .none
            }
        }
    }
}

public enum PageMode: String {
    case loading
    case left
    case right
    case normal
    case error
}
