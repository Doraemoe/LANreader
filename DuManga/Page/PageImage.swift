// Created on 14/4/21.

import SwiftUI
import GRDBQuery

struct PageImage: View {
    @AppStorage(SettingsKey.compressImageThreshold) var compressThreshold: CompressThreshold = .never

    @StateObject private var imageModel = PageImageModel()

    @Query<ArchiveImageRequest>
    private var archiveImage: ArchiveImage?

    private let id: String
    private let geometrySize: CGSize
    private let store = AppStore.shared

    init(id: String, geometrySize: CGSize) {
        self.id = id
        self.geometrySize = geometrySize
        _archiveImage = Query(ArchiveImageRequest(id: id))
    }

    var body: some View {
        // If not wrapped in ZStack, TabView will render ALL pages when initial load
        ZStack {
            Group {
                if let imageData = archiveImage?.image {
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
                    .progressViewStyle(.linear)
                    .frame(width: geometrySize.width * 0.8, height: geometrySize.height)
                    .tint(.primary)
                    .onAppear {
                        imageModel.load(id: id, compressThreshold: compressThreshold)
                    }
                }
            }
            .onChange(of: imageModel.reloadPageId) { reloadPageId in
                if reloadPageId == id {
                    imageModel.load(id: id, compressThreshold: compressThreshold)
                    store.dispatch(.trigger(action: .pageRefreshAction(id: "")))
                }
            }
        }
    }
}
