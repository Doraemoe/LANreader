// Created on 14/4/21.

import SwiftUI

struct PageImage: View {
    @StateObject private var imageModel = PageImageModel()

    private let id: String
    private let geometrySize: CGSize

    init(id: String, geometrySize: CGSize) {
        self.id = id
        self.geometrySize = geometrySize
    }

    var body: some View {
        if let imageData = imageModel.imageData {
                Image(uiImage: UIImage(data: imageData)!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometrySize.width)
                        .draggableAndZoomable(contentSize: geometrySize)
        } else {
            ProgressView(value: imageModel.progress, total: 1) {
                Text("loading")
            } currentValueLabel: {
                Text(String(format: "%.2f%%", imageModel.progress * 100))
            }
                    .frame(width: geometrySize.width * 0.8, height: geometrySize.height)
                    .tint(.primary)
                    .onAppear {
                        imageModel.load(id: id)
                    }
        }
    }
}
