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
            if let imageData = imageModel.imageData {
                Image(uiImage: UIImage(data: imageData)!)
                        .resizable()
            } else {
                Image(systemName: "photo")
                        .foregroundColor(.primary)
                        .task {
                            await imageModel.load(id: id, fromServer: false)
                        }
            }
        }
                .onAppear(perform: {
                    imageModel.load(state: store.state)
                })
                .onChange(of: imageModel.reloadThumbnailId, perform: { reload in
                    if reload == id {
                        Task {
                            await imageModel.load(id: id, fromServer: true)
                            store.dispatch(.trigger(action: .thumbnailRefreshAction(id: "")))
                        }
                    }
                })
    }
}

struct AsyncImage_Previews: PreviewProvider {
    static var previews: some View {
        ThumbnailImage(id: "id")
    }
}
