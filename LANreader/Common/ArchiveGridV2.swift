import ComposableArchitecture
import SwiftUI
import Logging

@Reducer struct GridFeature {
    private let logger = Logger(label: "GridFeature")

    @ObservableState
    struct State: Equatable, Identifiable {
        @Shared var archive: ArchiveItem

        var id: String { self.archive.id }
        var path: URL?
        var mode: ThumbnailMode = .loading
        let cached: Bool

        init(archive: Shared<ArchiveItem>, cached: Bool = false) {
            self._archive = archive
            self.path = LANraragiService.thumbnailPath?
                .appendingPathComponent("\(archive.id).heic", conformingTo: .heic)
            self.cached = cached
        }
    }

    enum Action: Equatable {
        case load(Bool)
        case finishLoading
        case finishRefreshArchive
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService
    @Dependency(\.appDatabase) var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                if force {
                    state.mode = .loading
                } else {
                    if FileManager.default.fileExists(atPath: state.path?.path(percentEncoded: false) ?? "") {
                        state.mode = .normal
                        return .none
                    }
                }
                if state.mode == .loading {
                    return .run(priority: .utility) { [id = state.id, path = state.path] send in
                        do {
                            let thumbnailUrl = try await service.retrieveArchiveThumbnail(id: id)
                                .serializingDownloadedFileURL()
                                .value
                            imageService.processThumbnail(thumbnailUrl: thumbnailUrl, destinationUrl: path!)
                            await send(.finishLoading)
                        } catch {
                            logger.error("failed to fetch thumbnail. \(error)")
                        }
                    }
                }
                return .none
            case .finishLoading:
                state.mode = .normal
                return .none
            case .finishRefreshArchive:
                state.archive.refresh = false
                return .none
            }
        }
    }
}

struct ArchiveGridV2: View {
    let store: StoreOf<GridFeature>

    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 2) {
            Text(buildTitle(archive: store.archive))
                .lineLimit(2)
                .foregroundStyle(Color.primary)
                .padding(4)
                .font(.caption)
            ZStack {
                if store.mode == .loading {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.primary)
                        .frame(height: 240)
                        .onAppear {
                            store.send(.load(false))
                        }
                } else {
                    if let uiImage = UIImage(contentsOfFile: store.path?.path(percentEncoded: false) ?? "") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(Color.primary)
                            .frame(height: 240)
                    }
                }
            }
            .onChange(of: store.archive.refresh) { _, newValue in
                if newValue {
                    store.send(.load(true))
                    store.send(.finishRefreshArchive)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary, lineWidth: 2)
                .opacity(0.9)
        )
    }

    func buildTitle(archive: ArchiveItem) -> String {
        var title = archive.name
        if store.cached {
            return title
        }
        if archive.pagecount == archive.progress {
            title = "👑 " + title
        } else if archive.progress < 2 {
            title = "🆕 " + title
        }
        return title
    }
}

enum ThumbnailMode: String {
    case loading
    case normal
}
