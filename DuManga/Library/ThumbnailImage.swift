// Created 17/10/20

import SwiftUI

struct ThumbnailImage: View {
    @StateObject private var imageModel = ThumbnailImageModel()

    @EnvironmentObject var trigger: ArchiveTrigger

    private let id: String

    init(id: String) {
        self.id = id
    }

    var body: some View {
        if imageModel.imageData != nil {
            Image(uiImage: UIImage(data: imageModel.imageData!)!)
                    .resizable()
                    .onChange(of: trigger.triggerThumbnailReload, perform: { reload in
                        if reload == id {
                            Task {
                                await imageModel.load(id: id, fromServer: true)
                                trigger.triggerThumbnailReload = ""
                            }
                        }
                    })
        } else {
            Image(systemName: "photo")
                    .foregroundColor(.primary)
                    .task {
                        await imageModel.load(id: id, fromServer: false)
                    }
                    .onChange(of: trigger.triggerThumbnailReload, perform: { reload in
                        if reload == id {
                            Task {
                                await imageModel.load(id: id, fromServer: true)
                                trigger.triggerThumbnailReload = ""
                            }
                        }
                    })
        }
    }
}

struct AsyncImage_Previews: PreviewProvider {
    static var previews: some View {
        ThumbnailImage(id: "id")
    }
}
