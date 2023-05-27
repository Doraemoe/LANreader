import Foundation
import UIKit
import CoreGraphics
import func AVFoundation.AVMakeRect

func resizeImage(data: Data, threshold: CompressThreshold) -> Data {
    if threshold == .never {
        return data
    }

    guard let image = UIImage(data: data) else { return data }
    let screenRect = AVMakeRect(aspectRatio: image.size, insideRect: UIScreen.main.bounds)
    let imagePixels = image.size.width * image.scale * image.size.height * image.scale
    let screenPixels = screenRect.size.width * UIScreen.main.scale * screenRect.size.height * UIScreen.main.scale

    let drawSize = CGSize(
        width: screenRect.size.width * Double(threshold.rawValue),
        height: screenRect.size.height * Double(threshold.rawValue)
    )

    if imagePixels > screenPixels * Double(threshold.rawValue) {
        let renderer = UIGraphicsImageRenderer(size: drawSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: drawSize))
        }.jpegData(compressionQuality: 0.8) ?? data
    } else {
        return data
    }
}
