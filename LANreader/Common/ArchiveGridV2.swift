import ComposableArchitecture
import SwiftUI
import Logging
import GRDB
import GRDBQuery

@Reducer public struct GridFeature: Sendable {
    private let logger = Logger(label: "GridFeature")

    @ObservableState
    public struct State: Equatable, Identifiable, Sendable {
        @Shared var archive: ArchiveItem
        var nonce = 0

        public var id: String { self.archive.id }
        let cached: Bool

        init(archive: Shared<ArchiveItem>, cached: Bool = false) {
            self._archive = archive
            self.cached = cached
        }
    }

    public enum Action: Equatable {
        case load(Bool)
        case increaseNonce
        case finishRefreshArchive
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(force):
                let exists = try? database.existsArchiveThumbnail(state.id)
                if !force && exists == true {
                    return .none
                }
                return .run(priority: .utility) { [id = state.id, isTank = state.id.isTankoubonArchiveId] send in
                    let thumbnailData = if isTank {
                        try await service.retrieveTankoubonThumbnail(id: id)
                    } else {
                        try await service.retrieveArchiveThumbnail(id: id)
                    }
                    guard let thumbnailData else {
                        return
                    }
                    var archiveThumbnail = ArchiveThumbnail(
                        id: id,
                        thumbnail: thumbnailData,
                        lastUpdate: Date()
                    )
                    try database.saveArchiveThumbnail(&archiveThumbnail)
                    await send(.increaseNonce)
                } catch: { error, _ in
                    logger.error("failed to fetch thumbnail. \(error)")
                }
            case .increaseNonce:
                state.nonce += 1
                return .none
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

    @Dependency(\.appDatabase) var database
    private let cornerRadius: CGFloat = 8

    init(store: StoreOf<GridFeature>) {
        self.store = store
    }

    var body: some View {
        let thumbnailObj = try? database.readArchiveThumbnail(store.id)
        ZStack {
            imageView(thumbnailObj: thumbnailObj)
                .id(store.nonce)
            bottomGradient
            topBadges
            titleOverlay
        }
        .aspectRatio(ArchiveGridMetrics.coverAspectRatio, contentMode: .fit)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 6)
        .padding(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: store.archive.refresh) { _, newValue in
            if newValue {
                store.send(.increaseNonce)
                store.send(.finishRefreshArchive)
            }
        }
    }

    private var bottomGradient: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0),
                Color.black.opacity(0.24),
                Color.black.opacity(0.78)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 128)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.archive.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

            if let progressFraction {
                progressBar(progressFraction)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    private var topBadges: some View {
        HStack(alignment: .top) {
            if let status {
                Image(systemName: status.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(status.tint, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)
            }

            Spacer(minLength: 6)

            if store.archive.pagecount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption2.weight(.semibold))
                    Text("\(store.archive.pagecount)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func imageView(thumbnailObj: ArchiveThumbnail?) -> some View {
        if let thumbnailData = thumbnailObj?.thumbnail, let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(uiColor: .secondarySystemGroupedBackground),
                        Color(uiColor: .tertiarySystemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image("noThumb")
                    .resizable()
                    .scaledToFit()
                    .padding(30)
                    .opacity(0.66)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                store.send(.load(false))
            }
        }
    }

    private var status: ArchiveGridStatus? {
        if store.cached {
            return .cached
        }
        if store.archive.pagecount > 0 && store.archive.pagecount == store.archive.progress {
            return .read
        }
        if store.archive.progress < 2 {
            return .new
        }
        return nil
    }

    private var progressFraction: Double? {
        guard store.cached == false,
              store.archive.pagecount > 0,
              store.archive.progress > 1 else {
            return nil
        }
        let fraction = Double(store.archive.progress) / Double(store.archive.pagecount)
        return min(max(fraction, 0), 1)
    }

    private var accessibilityLabel: Text {
        if let status {
            Text(verbatim: "\(store.archive.name), \(status.accessibilityLabel)")
        } else {
            Text(verbatim: store.archive.name)
        }
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                Capsule()
                    .fill(progressTint)
                    .frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 4)
    }

    private var progressTint: Color {
        if store.archive.pagecount > 0 && store.archive.pagecount == store.archive.progress {
            Color(uiColor: .systemGreen)
        } else {
            Color(uiColor: .systemBlue)
        }
    }
}

enum ArchiveGridMetrics {
    // Most manga/book covers are close to A/B-series paper proportions
    // (width / height ~= 0.707), which avoids vertical gaps for normal covers
    // while wide/double-page thumbnails still fit inside the card.
    static let coverAspectRatio: CGFloat = 0.707
}

private enum ArchiveGridStatus {
    case cached
    case read
    case new

    var systemImage: String {
        switch self {
        case .cached:
            "tray.full.fill"
        case .read:
            "crown.fill"
        case .new:
            "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .cached:
            Color(uiColor: .systemOrange)
        case .read:
            Color(uiColor: .systemGreen)
        case .new:
            Color(uiColor: .systemBlue)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cached:
            "cached"
        case .read:
            "read"
        case .new:
            "new"
        }
    }
}

struct ThumbnailRequest: ValueObservationQueryable {
    static var defaultValue: ArchiveThumbnail? { nil }

    var id: String

    func fetch(_ database: Database) throws -> ArchiveThumbnail? {
        try ArchiveThumbnail.fetchOne(database, key: id)
    }
}
