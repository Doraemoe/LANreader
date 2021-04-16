// Created on 14/4/21.

import SwiftUI

struct PageImage: View {
    @StateObject private var imageModel = PageImageModel()

    private let id: String

    init(id: String) {
        self.id = id
    }

    var body: some View {
        imageModel.image
                .resizable()
                .onAppear {
                    imageModel.load(id: id)
                }
                .onDisappear {
                    imageModel.unload()
                }
    }
}
