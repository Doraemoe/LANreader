// Created 17/10/20

import SwiftUI
import GRDBQuery

struct ThumbnailImage: View {
    @StateObject private var imageModel = ThumbnailImageModel()

    @Query<ArchiveThumbnailRequest>
    private var archiveThumbnail: ArchiveThumbnail?

    private let store = AppStore.shared
    private let id: String

    init(id: String) {
        self.id = id
        _archiveThumbnail = Query(ArchiveThumbnailRequest(id: id))
    }

    var body: some View {
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
        .onAppear {
            imageModel.connectStore()
        }
        .onDisappear {
            imageModel.disconnectStore()
        }
        .onChange(of: imageModel.reloadThumbnailId, perform: { reload in
            if reload == id {
                Task {
                    await imageModel.load(id: id)
                    store.dispatch(.trigger(action: .thumbnailRefreshAction(id: "")))
                }
            }
        })
    }
}
