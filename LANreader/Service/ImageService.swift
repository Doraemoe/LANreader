import Foundation
import UIKit
import CoreGraphics
import func AVFoundation.AVMakeRect
import Dependencies

class ImageService {
    private static var _shared: ImageService?

    func resizeImage(url: URL) {
        guard let image = UIImage(contentsOfFile: url.path) else { return }
        let screenRect = AVMakeRect(aspectRatio: image.size, insideRect: UIScreen.main.bounds)
        let imagePixels = image.size.width * image.scale * image.size.height * image.scale
        let screenPixels = screenRect.size.width * UIScreen.main.scale * screenRect.size.height * UIScreen.main.scale

        let drawSize = CGSize(
            width: screenRect.size.width * 2,
            height: screenRect.size.height * 2
        )

        if imagePixels > screenPixels * 2 {
            let renderer = UIGraphicsImageRenderer(size: drawSize)
            let data = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: drawSize))
            }.jpegData(compressionQuality: 0.8)
            try? data?.write(to: url)
        }
    }

    public static var shared: ImageService {
        if _shared == nil {
            _shared = ImageService()
        }
        return _shared!
    }
}

extension ImageService: DependencyKey {
    static let liveValue = ImageService.shared
    static let testValue = ImageService.shared
}

extension DependencyValues {
    var imageService: ImageService {
        get { self[ImageService.self] }
        set { self[ImageService.self] = newValue }
    }
}
