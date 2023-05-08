// Created 17/10/20

import SwiftUI

struct ThumbnailImage: View {
    @StateObject private var imageModel = ThumbnailImageModel()

    @EnvironmentObject var store: AppStore

    private let id: String

    init(id: String) {
        self.id = id
    }

    var body: some View {
        Group {
            if let imageData = imageModel.checkImageData(id: id) {
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
                .onAppear(perform: {
                    imageModel.load(state: store.state)
                })
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
