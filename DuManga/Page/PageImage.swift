// Created on 14/4/21.

import SwiftUI
import GRDBQuery

struct PageImage: View {
    @AppStorage(SettingsKey.compressImageThreshold) var compressThreshold: CompressThreshold = .never

    @State private var imageModel = PageImageModel()

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
                if let imageUrl = archiveImage?.image {
                    if let uiImage = UIImage(contentsOfFile: imageUrl) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometrySize.width)
                            .draggableAndZoomable(contentSize: geometrySize)
                    } else {
                        Image(systemName: "rectangle.slash")
                    }
                } else {
                    ProgressView(
                        value: imageModel.progress > 1 ? 1 : imageModel.progress,
                        total: 1
                    ) {
                        Text("loading")
                    } currentValueLabel: {
                        imageModel.progress > 1 ?
                        Text("downsampling") :
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
            .onAppear {
                imageModel.connectStore()
            }
            .onDisappear {
                imageModel.disconnectStore()
            }
            .onChange(of: imageModel.reloadPageId) {
                if imageModel.reloadPageId == id {
                    imageModel.load(id: id, compressThreshold: compressThreshold)
                    store.dispatch(.trigger(action: .pageRefreshAction(id: "")))
                }
            }
        }
    }
}
