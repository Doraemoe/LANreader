import UIKit
import Dependencies
import func AVFoundation.AVMakeRect

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

        let screenRect = UIScreen.main.bounds
        let rect = AVMakeRect(aspectRatio: image.size, insideRect: screenRect)
        let normalizedRect = CGRect(origin: .zero, size: rect.size)
        let renderer = UIGraphicsImageRenderer(size: normalizedRect.size)

        if skip {
            try? image.heicData()?.write(to: mainPath)
        } else {
            try? renderer.image { _ in
                image.draw(in: normalizedRect)
            }.heicData()?.write(to: mainPath)
        }

        if split && (image.size.width / image.size.height > 1.2) {
            let leftPath = destinationUrl.appendingPathComponent("\(pageNumber)-left", conformingTo: .image)
            let rightPath = destinationUrl.appendingPathComponent("\(pageNumber)-right", conformingTo: .image)
            if skip {
                try? image.leftHalf?.heicData()?.write(to: leftPath)
                try? image.rightHalf?.heicData()?.write(to: rightPath)
            } else {
                let leftImage = image.leftHalf
                let leftRect = AVMakeRect(
                    aspectRatio: leftImage?.size ?? .zero,
                    insideRect: screenRect
                )
                let normalizedLeftRect = CGRect(origin: .zero, size: leftRect.size)
                let leftRenderer = UIGraphicsImageRenderer(size: normalizedLeftRect.size)
                try? leftRenderer.image { _ in
                    leftImage?.draw(in: normalizedLeftRect)
                }.heicData()?.write(to: leftPath)

                let rightImage = image.rightHalf
                let rightRect = AVMakeRect(
                    aspectRatio: rightImage?.size ?? .zero,
                    insideRect: screenRect
                )
                let normalizedRightRect = CGRect(origin: .zero, size: rightRect.size)
                let rightRenderer = UIGraphicsImageRenderer(size: normalizedRightRect.size)
                try? rightRenderer.image { _ in
                    rightImage?.draw(in: normalizedRightRect)
                }.heicData()?.write(to: rightPath)
            }
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
