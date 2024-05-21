import ComposableArchitecture
import SwiftUI
import Logging

@Reducer struct GridFeature {
    private let logger = Logger(label: "GridFeature")
    private let thumbnailPath = LANraragiService.thumbnailPath!

    @ObservableState
    struct State: Equatable, Identifiable {
        @Shared var archive: ArchiveItem
        @Shared var archiveThumbnail: Data?

        var id: String { self.archive.id }
        let cached: Bool

        init(archive: Shared<ArchiveItem>, archiveThumbnail: Data? = nil, cached: Bool = false) {
            self._archive = archive
            self._archiveThumbnail = Shared(
                wrappedValue: archiveThumbnail,
                    .fileStorage(
                        LANraragiService.thumbnailPath!
                            .appendingPathComponent(archive.id, conformingTo: .image)
                    )
            )
            self.cached = cached
        }
    }

    enum Action: Equatable {
        case load(Bool)
        case setThumbnail(Data)
        case unload
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                if force {
                    state.archiveThumbnail = nil
                }
                if state.archiveThumbnail == nil {
                    return .run(priority: .utility) { [id = state.id] send in
                        do {
                            let imageData = try await service.retrieveArchiveThumbnail(id: id).serializingData().value
                            await send(.setThumbnail(imageData))
                        } catch {
                            logger.error("failed to fetch thumbnail. \(error)")
                        }
                    }
                }
                return .none
            case let .setThumbnail(thumbnail):
                state.archiveThumbnail = thumbnail
                return .none
            case .unload:
                state.archiveThumbnail = nil
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
                if let imageData = store.archiveThumbnail {
                    Image(uiImage: UIImage(data: imageData)!)
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
