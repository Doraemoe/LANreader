import Foundation
import UIKit
import CoreGraphics
import func AVFoundation.AVMakeRect
import Dependencies

class ImageService {
    private static var _shared: ImageService?

    // swiftlint:disable large_tuple
    func resizeImage(data: Data, split: Bool, skip: Bool) -> (Data, Data?, Data?) {
        var imageData: Data = data
        var leftImageData: Data?
        var rightImageData: Data?
        guard !skip, let image = UIImage(data: data) else { return (imageData, leftImageData, rightImageData) }
        let screenRect = AVMakeRect(aspectRatio: image.size, insideRect: UIScreen.main.bounds)
        let imagePixels = image.size.width * image.scale * image.size.height * image.scale
        let screenPixels = screenRect.size.width * UIScreen.main.scale * screenRect.size.height * UIScreen.main.scale

        let drawSize = CGSize(
            width: screenRect.size.width * 1.5,
            height: screenRect.size.height * 1.5
        )

        if imagePixels > screenPixels * 2 {
            let renderer = UIGraphicsImageRenderer(size: drawSize)
            let image = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: drawSize))
            }
            imageData = image.jpegData(compressionQuality: 0.8) ?? data
        }

        if split && (image.size.width / image.size.height > 1.2) {
            leftImageData = image.leftHalf?.jpegData(compressionQuality: 0.8)
            rightImageData = image.rightHalf?.jpegData(compressionQuality: 0.8)
        }

        return (imageData, leftImageData, rightImageData)
    }
    // swiftlint:enable large_tuple

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

extension UIImage {
    var topHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: .zero,
                size: CGSize(width: size.width, height: size.height / 2)
            )
        )?.image
    }
    var bottomHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: CGPoint(x: .zero, y: size.height - (size.height/2).rounded()),
                size: CGSize(width: size.width, height: size.height - (size.height/2).rounded())
            )
        )?.image
    }
    var leftHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: .zero,
                size: CGSize(width: size.width/2, height: size.height)
            )
        )?.image
    }
    var rightHalf: UIImage? {
        cgImage?.cropping(
            to: CGRect(
                origin: CGPoint(x: size.width - (size.width/2).rounded(), y: .zero),
                size: CGSize(width: size.width - (size.width/2).rounded(), height: size.height)
            )
        )?.image
    }
}

extension CGImage {
    var image: UIImage { .init(cgImage: self) }
}
