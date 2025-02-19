import UIKit
import Dependencies

class ImageService {
    private static var _shared: ImageService?

    func processThumbnail(thumbnailUrl: URL, destinationUrl: URL) {
        guard let image = UIImage(contentsOfFile: thumbnailUrl.path(percentEncoded: false)) else { return }
        try? image.heicData()?.write(to: destinationUrl)
    }

    func heicDataOfImage(url: URL) -> Data? {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        return image.heicData()
    }

    func resizeImage(imageUrl: URL, destinationUrl: URL, pageNumber: String, split: Bool) -> Bool {
        try? FileManager.default.createDirectory(at: destinationUrl, withIntermediateDirectories: true)
        let mainPath = destinationUrl.appendingPathComponent("\(pageNumber).heic", conformingTo: .heic)

        guard let image = UIImage(contentsOfFile: imageUrl.path(percentEncoded: false)) else { return false }
        var splitted = false

        try? image.heicData()?.write(to: mainPath)

        if split && (image.size.width / image.size.height > 1.2) {
            let leftPath = destinationUrl.appendingPathComponent("\(pageNumber)-left.heic", conformingTo: .heic)
            let rightPath = destinationUrl.appendingPathComponent("\(pageNumber)-right.heic", conformingTo: .heic)

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
