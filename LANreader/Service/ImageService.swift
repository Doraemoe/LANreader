import UIKit
import Dependencies
import ImageIO
import UniformTypeIdentifiers

final class ImageService: Sendable {
    static let shared = ImageService()

    func heicDataOfImage(url: URL) -> Data? {
        guard let image = previewImage(url: url) else { return nil }
        return image.heicData()
    }

    func resizeImage(
        imageUrl: URL,
        imageData: Data? = nil,
        destinationUrl: URL,
        pageNumber: String,
        split: Bool
    ) -> Bool {
        try? FileManager.default.createDirectory(at: destinationUrl, withIntermediateDirectories: true)
        let mainPath = destinationUrl.appendingPathComponent("\(pageNumber).heic", conformingTo: .heic)
        let mainGifPath = destinationUrl.appendingPathComponent("\(pageNumber).gif", conformingTo: .gif)
        let leftPath = destinationUrl.appendingPathComponent("\(pageNumber)-left.heic", conformingTo: .heic)
        let rightPath = destinationUrl.appendingPathComponent("\(pageNumber)-right.heic", conformingTo: .heic)

        if imageData == nil, isGIF(url: imageUrl), let gifData = try? Data(contentsOf: imageUrl) {
            try? gifData.write(to: mainGifPath, options: .atomic)
            removeIfExists(mainPath)
            removeIfExists(leftPath)
            removeIfExists(rightPath)
            return false
        }

        let image: UIImage
        if imageData != nil {
            guard let convertImage = UIImage(data: imageData!) else { return false }
            image = convertImage
        } else {
            guard let convertImage = UIImage(contentsOfFile: imageUrl.path(percentEncoded: false)) else { return false }
            image = convertImage
        }

        var splitted = false

        removeIfExists(mainGifPath)
        try? image.heicData()?.write(to: mainPath)

        if split && (image.size.width / image.size.height > 1.2) {
            try? image.leftHalf?.heicData()?.write(to: leftPath)
            try? image.rightHalf?.heicData()?.write(to: rightPath)

            splitted = true
        } else {
            removeIfExists(leftPath)
            removeIfExists(rightPath)
        }
        return splitted
    }

    private func previewImage(url: URL) -> UIImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            isGIF(source),
            let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return UIImage(cgImage: frame)
        }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    private func isGIF(url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return isGIF(source)
    }

    private func isGIF(_ source: CGImageSource) -> Bool {
        guard let type = CGImageSourceGetType(source) else { return false }
        return UTType(type as String)?.conforms(to: .gif) == true
    }

    private func removeIfExists(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: url)
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
