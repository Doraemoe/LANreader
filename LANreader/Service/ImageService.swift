import Foundation
import UIKit
import CoreGraphics
import Dependencies

class ImageService {
    private static var _shared: ImageService?

    func resizeImage(imageUrl: URL, destinationUrl: URL, pageNumber: String, split: Bool, skip: Bool) -> Bool {
        try? FileManager.default.createDirectory(at: destinationUrl, withIntermediateDirectories: true)
        let mainPath = destinationUrl.appendingPathComponent(pageNumber, conformingTo: .image)

        // if use UIImage(contentsOfFile:) directly, IOSurface creation failed warning may happen
        // Same thing happens in PageImageV2
        guard let imageData = try? Data(contentsOf: imageUrl),
                let image = UIImage(data: imageData) else { return false }
        var splitted = false
        if !skip {
            try? image.heicData()?.write(to: mainPath)
        } else {
            try? FileManager.default.moveItem(at: imageUrl, to: mainPath)
        }

        if split && (image.size.width / image.size.height > 1.2) {
            let leftPath = destinationUrl.appendingPathComponent("\(pageNumber)-left", conformingTo: .image)
            let rightPath = destinationUrl.appendingPathComponent("\(pageNumber)-right", conformingTo: .image)
            try? image.leftHalf?.heicData()?.write(to: leftPath)
            try? image.rightHalf?.heicData()?.write(to: rightPath)
            splitted = true
        }
        return splitted
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
