import ComposableArchitecture
import SwiftUI
import Logging

struct GridFeature: Reducer {
    private let logger = Logger(label: "GridFeature")
    struct State: Equatable, Identifiable {
        var archive: ArchiveItem
        var archiveThumbnail: ArchiveThumbnail?

        var id: String { self.archive.id }
    }

    enum Action: Equatable {
        case load(String, Bool)
        case setThumbnail(ArchiveThumbnail)
        case unload
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(id, force):
                if !force {
                    do {
                        state.archiveThumbnail = try database.readArchiveThumbnail(id)
                    } catch {
                        logger.error("failed to load thumbnail. id=\(id) \(error)")
                    }
                }
                if force || state.archiveThumbnail == nil {
                    return .run { send in
                        do {
                            let imageData = try await service.retrieveArchiveThumbnail(id: id).serializingData().value
                            var thumbnail = ArchiveThumbnail(id: id, thumbnail: imageData, lastUpdate: Date())
                            do {
                                try database.saveArchiveThumbnail(&thumbnail)
                            } catch {
                                logger.warning("failed to save thumbnail to db. id=\(id) \(error)")
                            }
                            await send(.setThumbnail(thumbnail))
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
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            VStack(alignment: HorizontalAlignment.center, spacing: 2) {
                Text(buildTitle(archive: viewStore.archive))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .padding(4)
                    .font(.caption)
                Group {
                    if let imageData = viewStore.archiveThumbnail?.thumbnail {
                        Image(uiImage: UIImage(data: imageData)!)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.primary)
                            .onAppear {
                                viewStore.send(.load(viewStore.id, false))
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
    }

    func buildTitle(archive: ArchiveItem) -> String {
        var title = archive.name
        if archive.pagecount == archive.progress {
            title = "👑 " + title
        } else if archive.progress < 2 {
            title = "🆕 " + title
        }
        return title
    }
}
