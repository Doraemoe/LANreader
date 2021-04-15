// Created on 14/4/21.

import SwiftUI

struct PageImage: View {
    @StateObject private var imageModel: PageImageModel

    init(pageId: String) {
        _imageModel = StateObject(wrappedValue: PageImageModel(pageId: pageId))
    }

    var body: some View {
        imageModel.image
                .resizable()
    }
}
