// Created 17/10/20
import ComposableArchitecture
import SwiftUI
import GRDBQuery

struct ThumbnailImage: View {
    private let imageModel = ThumbnailImageModel()

    @Query<ArchiveThumbnailRequest>
    private var archiveThumbnail: ArchiveThumbnail?

    private let store = AppFeature.shared
    private let id: String

    init(id: String) {
        self.id = id
        _archiveThumbnail = Query(ArchiveThumbnailRequest(id: id))
    }
    
    struct ViewState: Equatable {
        let reloadThumbnailId: String
        init(state: AppFeature.State) {
            self.reloadThumbnailId = state.trigger.thumbnailId
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            Group {
                if let imageData = archiveThumbnail?.thumbnail {
                    Image(uiImage: UIImage(data: imageData)!)
                        .resizable()
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.primary)
                        .task {
                            await imageModel.load(id: id)
                        }
                }
            }
            .onChange(of: viewStore.reloadThumbnailId) {
                if viewStore.reloadThumbnailId == id {
                    Task {
                        await imageModel.load(id: id)
                        viewStore.send(.trigger(.thumbnailRefreshAction("")))
                    }
                }
            }
        }
    }
}
