//Created 17/10/20

import SwiftUI

struct ThumbnailImage: View {
    @StateObject private var imageModel: ThumbnailImageModel

    init(id: String) {
        _imageModel = StateObject(wrappedValue: ThumbnailImageModel(id: id))
    }

    var body: some View {
        imageModel.image
            .resizable()
            .onAppear(perform: {
                imageModel.load()
            })
            .onDisappear(perform: {
                imageModel.unload()
            })
    }
}

struct AsyncImage_Previews: PreviewProvider {
    static var previews: some View {
        ThumbnailImage(id: "id")
    }
}
