import ComposableArchitecture
import SwiftUI
import Logging
import GRDB
import GRDBQuery

@Reducer public struct GridFeature {
    private let logger = Logger(label: "GridFeature")

    @ObservableState
    public struct State: Equatable, Identifiable {
        @Shared var archive: ArchiveItem

        public var id: String { self.archive.id }
        let cached: Bool

        init(archive: Shared<ArchiveItem>, cached: Bool = false) {
            self._archive = archive
            self.cached = cached
        }
    }

    public enum Action: Equatable {
        case load(Bool)
        case finishRefreshArchive
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService
    @Dependency(\.appDatabase) var database

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                let exists = try? database.existsArchiveThumbnail(state.id)
                if !force && exists == true {
                    return .none
                }
                return .run(priority: .utility) { [id = state.id] _ in
                    let thumbnailUrl = try await service.retrieveArchiveThumbnail(id: id)
                        .serializingDownloadedFileURL()
                        .value
                    var archiveThumbnail = ArchiveThumbnail(
                        id: id,
                        thumbnail: imageService.heicDataOfImage(url: thumbnailUrl) ?? Data(),
                        lastUpdate: Date()
                    )
                    try database.saveArchiveThumbnail(&archiveThumbnail)
                } catch: { error, _ in
                    logger.error("failed to fetch thumbnail. \(error)")
                }
            case .finishRefreshArchive:
                state.$archive.withLock {
                    $0.refresh = false
                }
                return .none
            }
        }
    }
}

struct ArchiveGridV2: View {
    let store: StoreOf<GridFeature>

    @Query<ThumbnailRequest> var thumbnailObj: ArchiveThumbnail?

    init(store: StoreOf<GridFeature>) {
        self.store = store
        self._thumbnailObj = Query(ThumbnailRequest(id: store.id))
    }

    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 2) {
            Text(buildTitle(archive: store.archive))
                .lineLimit(2)
                .foregroundStyle(Color.primary)
                .padding(4)
                .font(.caption)
            ZStack {
                if let thumbnailData = thumbnailObj?.thumbnail, let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.primary)
                        .frame(height: 240)
                        .onAppear {
                            store.send(.load(false))
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

struct ThumbnailRequest: ValueObservationQueryable {
    static var defaultValue: ArchiveThumbnail? { nil }

    var id: String

    func fetch(_ database: Database) throws -> ArchiveThumbnail? {
        try ArchiveThumbnail.fetchOne(database, key: id)
    }
}
