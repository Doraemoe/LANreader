import ComposableArchitecture
import Alamofire
import SwiftUI
import Logging

@Reducer public struct PageFeature: Sendable {
    private let logger = Logger(label: "PageFeature")

    @ObservableState
    public struct State: Equatable, Identifiable, Sendable {
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.translationEnabled)) var translationEnabled = false

        let pageId: String
        let sourceArchiveId: String
        let sourcePageNumber: Int
        let suffix: String
        let pageNumber: Int
        var loading: Bool = false
        var progress: Double = 0
        var errorMessage = ""
        var pageMode: PageMode
        var pendingSplitMode: PageMode?
        let cached: Bool
        var imageLoaded = false
        var translationStatus = ""
        var stamps: [ArchiveStamp] = []
        var stampsLoading = false
        var stampsLoaded = false
        /// Aspect ratio (height / width) of the source image, measured from the image header.
        var imageAspectRatio: Double?

        public var id: String {
            "\(pageId)-\(suffix)"
        }

        /// Aspect ratio of what this page actually renders. Split pages show half of the source
        /// image width, so they are twice as tall relative to their width.
        var displayAspectRatio: Double? {
            guard let imageAspectRatio else { return nil }
            return pageMode.isSplitMode
                ? ReaderPageLayout.splitAspectRatio(for: imageAspectRatio)
                : imageAspectRatio
        }

        let folder: URL?

        init(
            archiveId: String,
            pageId: String,
            pageNumber: Int,
            sourceArchiveId: String? = nil,
            sourcePageNumber: Int? = nil,
            pageMode: PageMode = .loading,
            cached: Bool = false
        ) {
            self.pageId = pageId
            self.sourceArchiveId = sourceArchiveId ?? archiveId
            self.sourcePageNumber = sourcePageNumber ?? pageNumber
            self.pageNumber = pageNumber
            self.pageMode = pageMode
            self.suffix = pageMode.identitySuffix
            self.cached = cached
            let imagePath = if cached {
                LANraragiService.cachePath
            } else {
                LANraragiService.downloadPath
            }
            self.folder = imagePath?.appendingPathComponent(archiveId, conformingTo: .folder)
        }
    }

    public enum Action: Equatable {
        case load(Bool)
        case loadStamps
        case stampsLoaded([ArchiveStamp])
        case stampsLoadFailed(endpointUnavailable: Bool)
        case setIsLoading(Bool)
        case subscribeToProgress(DownloadRequest)
        case cancelSubscribeImageProgress
        case setProgress(Double)
        case setStoredImage(shouldDisplayAsSplitPages: Bool)
        case storedImageResolved(shouldDisplayAsSplitPages: Bool)
        case setError(String)
        case setTranslationStatus(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService
    @Dependency(\.translatorService) var translatorService

    public enum CancelId: Sendable {
        case imageLoad
        case imageProgress
        case stampsLoad
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadStamps:
                guard !state.cached, !state.stampsLoading, !state.stampsLoaded else {
                    return .none
                }
                state.stampsLoading = true
                let archiveId = state.sourceArchiveId
                let page = state.sourcePageNumber
                return .run { send in
                    do {
                        let response = try await service.retrieveStamps(id: archiveId, page: page).value
                        await send(.stampsLoaded(response.result))
                    } catch is CancellationError {
                        return
                    } catch {
                        logger.warning(
                            "failed to load stamps. archive=\(archiveId) page=\(page) \(error.localizedDescription)"
                        )
                        await send(.stampsLoadFailed(endpointUnavailable: error.asAFError?.responseCode == 404))
                    }
                }
                .cancellable(id: CancelId.stampsLoad, cancelInFlight: true)
            case let .stampsLoaded(stamps):
                state.stamps = stamps
                state.stampsLoading = false
                state.stampsLoaded = true
                return .none
            case let .stampsLoadFailed(endpointUnavailable):
                state.stampsLoading = false
                // Avoid repeated requests only when the server does not expose this endpoint.
                // Transient failures remain retryable when stamps are shown again.
                state.stampsLoaded = endpointUnavailable
                return .none
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
                if !force, state.pageMode != .loading {
                    state.loading = false
                    state.imageLoaded = true
                    return .none
                }

                state.loading = true
                state.errorMessage = ""
                state.imageLoaded = false

                if force {
                    state.pageMode = .loading
                    state.imageAspectRatio = nil
                } else if state.pageMode == .loading {
                    let normalPath = imageService.storedImagePath(
                        folderUrl: state.folder,
                        pageNumber: String(state.pageNumber)
                    )

                    if let normalPath {
                        let shouldDisplayAsSplitPages = state.splitImage
                            && imageService.shouldSplitWideImage(imageUrl: normalPath)
                        state.imageAspectRatio = imageService.imageAspectRatio(imageUrl: normalPath)
                        return applyStoredImage(
                            shouldDisplayAsSplitPages: shouldDisplayAsSplitPages,
                            state: &state
                        )
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
                            await send(.cancelSubscribeImageProgress)

                            do {
                                let task = await service.fetchArchivePage(
                                    page: state.pageId,
                                    pageNumber: state.sourcePageNumber
                                )
                                await send(.subscribeToProgress(task))
                                let imageUrl = try await task
                                    .serializingDownloadedFileURL()
                                    .value
                                await send(.cancelSubscribeImageProgress)

                                let animated = imageService.isAnimatedImage(imageUrl: imageUrl)
                                var translated: Data?
                                if state.translationEnabled && !animated {
                                    await send(.setProgress(2.0))

                                    guard let request = await translatorService.translatePage(original: imageUrl) else {
                                        await send(
                                            .setError(
                                                String(localized: "archive.page.translate.request.failed")
                                            )
                                        )
                                        return
                                    }

                                    let handler = TranslationStreamHandler()
                                    let statusStream = await handler.processStreamResponse(request)
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

                                let storedPageImage = imageService.storePageImage(
                                    imageUrl: imageUrl,
                                    imageData: translated,
                                    destinationUrl: state.folder!,
                                    pageNumber: String(state.pageNumber),
                                    splitWideImages: state.splitImage
                                )
                                await send(
                                    .setStoredImage(
                                        shouldDisplayAsSplitPages: storedPageImage?.shouldDisplayAsSplitPages ?? false
                                    )
                                )
                            } catch is CancellationError {
                                await send(.cancelSubscribeImageProgress)
                            } catch {
                                logger.error("failed to load image. \(error)")
                                await send(.cancelSubscribeImageProgress)
                                await send(.setError(error.localizedDescription))
                            }
                        }
                        .cancellable(id: CancelId.imageLoad, cancelInFlight: true)
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
            case let .setStoredImage(shouldDisplayAsSplitPages):
                return applyStoredImage(
                    shouldDisplayAsSplitPages: shouldDisplayAsSplitPages,
                    state: &state
                )
            case let .setError(message):
                state.loading = false
                state.imageLoaded = true
                state.errorMessage = message
                state.pendingSplitMode = nil
                return .none
            case .storedImageResolved:
                return .none
            case let .setTranslationStatus(status):
                state.translationStatus = status
                return .none
            }
        }
    }

    private func applyStoredImage(
        shouldDisplayAsSplitPages: Bool,
        state: inout State
    ) -> Effect<Action> {
        state.progress = 0
        state.loading = false
        state.imageLoaded = true
        if state.imageAspectRatio == nil {
            state.imageAspectRatio = storedImageAspectRatio(state: state)
        }

        if shouldDisplayAsSplitPages {
            return .send(.storedImageResolved(shouldDisplayAsSplitPages: true))
        }

        state.pageMode = .normal
        state.pendingSplitMode = nil
        return .send(.storedImageResolved(shouldDisplayAsSplitPages: false))
    }

    /// Header-only read of the stored file, so the reader knows the page height without decoding it.
    private func storedImageAspectRatio(state: State) -> Double? {
        guard let imageUrl = imageService.storedImagePath(
            folderUrl: state.folder,
            pageNumber: String(state.pageNumber)
        ) else {
            return nil
        }
        return imageService.imageAspectRatio(imageUrl: imageUrl)
    }
}

public enum PageMode: String, Sendable {
    case loading
    case left
    case right
    case normal
    case error
}

extension PageMode {
    var identitySuffix: String {
        switch self {
        case .loading:
            PageMode.normal.rawValue
        case .left, .right, .normal, .error:
            rawValue
        }
    }

    var isSplitMode: Bool {
        self == .left || self == .right
    }

    var splitSiblingMode: PageMode? {
        switch self {
        case .left:
            return .right
        case .right:
            return .left
        case .loading, .normal, .error:
            return nil
        }
    }

    static func preferredSplitMode(priorityLeft: Bool) -> PageMode {
        priorityLeft ? .left : .right
    }

    static func trailingSplitMode(priorityLeft: Bool) -> PageMode {
        priorityLeft ? .right : .left
    }
}
