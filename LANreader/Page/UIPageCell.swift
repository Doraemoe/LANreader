import Combine
import ComposableArchitecture
import SwiftUI
import UIKit
import Logging
import ImageIO

class UIPageCell: UICollectionViewCell {
    static let reuseIdentifier = "UIPageCell"
    private static let decodedImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.name = "LANreader.UIPageCell.decodedImageCache"
        cache.countLimit = 120
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()
    private static let decodedAnimatedCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.name = "LANreader.UIPageCell.decodedAnimatedCache"
        cache.countLimit = 20
        cache.totalCostLimit = 512 * 1024 * 1024
        return cache
    }()
    private static let animatedDecodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LANreader.UIPageCell.animatedDecode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var store: StoreOf<PageFeature>?
    private var useAspectHeight = false

    private let logger = Logger(label: "UIPageCell")

    private var cancellables: Set<AnyCancellable> = []

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.minimumZoomScale = 1.0
        view.maximumZoomScale = 3.0
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        return view
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()
    private lazy var animatedRenderer = AnimatedRenderer(imageView: imageView)

    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.progressTintColor = .label
        return view
    }()

    private let progressViewLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .natural
        label.textColor = .label
        return label
    }()

    private func cancelSubscriptions() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupImageView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupImageView() {
        contentView.addSubview(scrollView)
        scrollView.addSubview(imageView)
        contentView.addSubview(progressView)
        contentView.addSubview(progressViewLabel)

        scrollView.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressViewLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            progressView.centerXAnchor.constraint(
                equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(
                equalTo: contentView.widthAnchor, multiplier: 0.9),

            progressViewLabel.leadingAnchor.constraint(
                equalTo: progressView.leadingAnchor),
            progressViewLabel.topAnchor.constraint(
                equalTo: progressView.bottomAnchor, constant: 8)
        ])
    }

    func configure(with store: StoreOf<PageFeature>, useAspectHeight: Bool) {
        // Tear down any existing observation from a previous page assignment
        cancelSubscriptions()
        animatedRenderer.reset()
        self.store = store
        self.useAspectHeight = useAspectHeight
        animatedRenderer.setAnimationActive(true)
        imageView.image = nil
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
        setupObserve(store: store)
    }

    // swiftlint:disable function_body_length
    func setupObserve(store: StoreOf<PageFeature>) {
        store.publisher.progress
            .sink { [weak self] _ in
                guard let self else { return }
                // Ensure the cell is still showing this store (may have been reused)
                guard self.store === store else { return }
                guard !store.imageLoaded else { return }

                imageView.isHidden = true
                progressView.isHidden = false
                progressViewLabel.isHidden = false
                progressView.progress = Float(store.progress)
                progressViewLabel.text = store.progress > 1 ? String(localized: "translating") : String(
                    format: "%.2f%%", store.progress * 100)
            }
            .store(in: &cancellables)

        store.publisher.translationStatus
            .sink { [weak self] status in
                guard let self else { return }
                guard self.store === store else { return }
                guard !status.isEmpty else { return }

                progressViewLabel.text = status
            }
            .store(in: &cancellables)

        store.publisher.imageLoaded
            .sink { [weak self] loaded in
                guard let self else { return }
                guard self.store === store else { return }
                guard loaded else { return }

                if store.errorMessage.isEmpty {
                    imageView.isHidden = false
                    progressView.isHidden = true
                    progressViewLabel.isHidden = true
                    let contentPath = {
                        switch store.pageMode {
                        case .left:
                            return store.pathLeft
                        case .right:
                            return store.pathRight
                        default:
                            return store.path
                        }
                    }()
                    let selectedPath = resolvedContentPath(store: store, basePath: contentPath)
                    if let path = selectedPath {
                        if Self.isAnimatedContainer(path: path) {
                            loadAnimatedImage(path: path, store: store)
                        } else if let uiImage = loadImage(path: path) {
                            animatedRenderer.showStaticImage(uiImage)
                        } else {
                            animatedRenderer.showPlaceholder()
                        }
                    } else {
                        animatedRenderer.showPlaceholder()
                    }
                } else {
                    animatedRenderer.reset()
                    progressView.isHidden = true
                    progressViewLabel.text = store.errorMessage
                }
            }
            .store(in: &cancellables)
    }
    // swiftlint:enable function_body_length

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelSubscriptions()
        animatedRenderer.reset()
        store = nil
        useAspectHeight = false
        animatedRenderer.setAnimationActive(true)
        imageView.image = nil
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        guard useAspectHeight else { return attributes }
        if let image = imageView.image {
            let width = layoutAttributes.frame.width
            let height = width * (image.size.height / image.size.width)
            attributes.frame.size.height = height
        }
        return attributes
    }

    private func resolvedContentPath(store: StoreOf<PageFeature>, basePath: URL?) -> URL? {
        if store.pageMode == .normal,
            let mainPath = store.existingMainPath {
            return mainPath
        }
        if let basePath,
            FileManager.default.fileExists(atPath: basePath.path(percentEncoded: false)) {
            return basePath
        }
        return nil
    }

    private func loadImage(path: URL) -> UIImage? {
        if let type = PageMainImageType(rawValue: path.pathExtension.lowercased()),
            type.isAnimatedContainer {
            return nil
        }
        let filePath = path.path(percentEncoded: false)
        let cacheKey = filePath as NSString
        if let image = Self.decodedImageCache.object(forKey: cacheKey) {
            return image
        }
        guard let image = UIImage(contentsOfFile: filePath) else { return nil }
        Self.decodedImageCache.setObject(image, forKey: cacheKey, cost: image.memoryCostEstimate)
        return image
    }

    private func loadAnimatedImage(path: URL, store: StoreOf<PageFeature>) {
        let filePath = path.path(percentEncoded: false)

        if let cachedAnimated = Self.decodedAnimatedCache.object(forKey: filePath as NSString) {
            animatedRenderer.showAnimatedFromCache(cachedAnimated)
            return
        }

        let requestId = animatedRenderer.beginAnimatedLoad(poster: Self.animatedPoster(path: path))

        let decodeOperation = BlockOperation()
        decodeOperation.addExecutionBlock { [weak decodeOperation] in
            guard let operation = decodeOperation,
                !operation.isCancelled
            else { return }

            guard let animated = UIImage.animatedImage(path: path) else { return }
            let memoryCost = animated.animatedMemoryCostEstimate
            guard !operation.isCancelled else { return }

            Task { @MainActor [weak self, weak decodeOperation] in
                guard let self,
                    let operation = decodeOperation,
                    !operation.isCancelled
                else { return }
                guard self.store === store else { return }
                guard self.animatedRenderer.canApplyDecodeResult(requestId: requestId) else { return }

                let cacheKey = filePath as NSString
                Self.decodedAnimatedCache.setObject(animated, forKey: cacheKey, cost: memoryCost)
                self.animatedRenderer.finishAnimatedLoad(with: animated)
            }
        }

        animatedRenderer.setDecodeOperation(decodeOperation)
        Self.animatedDecodeQueue.addOperation(decodeOperation)
    }

    func setAnimationActive(_ active: Bool) {
        animatedRenderer.setAnimationActive(active)
    }

    private nonisolated static func isAnimatedContainer(path: URL) -> Bool {
        guard let type = PageMainImageType(rawValue: path.pathExtension.lowercased()) else {
            return false
        }
        return type.isAnimatedContainer
    }

    private nonisolated static func animatedPoster(path: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
            let frame = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            guard let fallback = UIImage(contentsOfFile: path.path(percentEncoded: false)) else {
                return nil
            }
            if let cgImage = fallback.cgImage {
                return UIImage(cgImage: cgImage)
            }
            return fallback.images?.first ?? fallback
        }
        return UIImage(cgImage: frame)
    }
}

@MainActor
private final class AnimatedRenderer {
    private weak var imageView: UIImageView?
    private var decodeRequestId: UInt = 0
    private var decodeOperation: Operation?
    private var isAnimationActive = true
    private var posterImage: UIImage?
    private var playbackImage: UIImage?

    init(imageView: UIImageView) {
        self.imageView = imageView
    }

    func reset() {
        cancelDecode()
        posterImage = nil
        playbackImage = nil
        imageView?.stopAnimating()
    }

    func setAnimationActive(_ active: Bool) {
        guard isAnimationActive != active else { return }
        isAnimationActive = active
        applyAnimationState()
    }

    func showStaticImage(_ image: UIImage) {
        reset()
        imageView?.image = image
    }

    func showPlaceholder() {
        reset()
        imageView?.image = UIImage(systemName: "rectangle.slash")
    }

    func showAnimatedFromCache(_ image: UIImage) {
        cancelDecode()
        playbackImage = image
        posterImage = image.images?.first ?? image
        applyAnimationState()
    }

    @discardableResult
    func beginAnimatedLoad(poster: UIImage?) -> UInt {
        cancelDecode()
        playbackImage = nil
        posterImage = poster
        if let poster {
            imageView?.image = poster
        } else {
            imageView?.image = UIImage(systemName: "rectangle.slash")
        }
        imageView?.stopAnimating()
        return decodeRequestId
    }

    func setDecodeOperation(_ operation: Operation) {
        decodeOperation = operation
    }

    func canApplyDecodeResult(requestId: UInt) -> Bool {
        requestId == decodeRequestId
    }

    func finishAnimatedLoad(with image: UIImage) {
        playbackImage = image
        if posterImage == nil {
            posterImage = image.images?.first ?? image
        }
        applyAnimationState()
        decodeOperation = nil
    }

    private func cancelDecode() {
        decodeRequestId &+= 1
        decodeOperation?.cancel()
        decodeOperation = nil
    }

    private func applyAnimationState() {
        guard let imageView else { return }
        guard let animated = playbackImage else {
            imageView.stopAnimating()
            return
        }

        if isAnimationActive {
            imageView.image = animated
            imageView.startAnimating()
        } else {
            imageView.image = posterImage ?? animated.images?.first ?? animated
            imageView.stopAnimating()
        }
    }
}

extension UIPageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

private extension UIImage {
    var memoryCostEstimate: Int {
        Int(size.width * size.height * scale * scale * 4)
    }

    var animatedMemoryCostEstimate: Int {
        guard let frames = images, !frames.isEmpty else { return memoryCostEstimate }
        return frames.reduce(0) { partial, frame in
            partial + frame.memoryCostEstimate
        }
    }

    static func animatedImage(path: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(path as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        if count == 1, let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return UIImage(cgImage: cgImage)
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var duration: Double = 0

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(source: source, at: index)
        }

        guard !frames.isEmpty else { return nil }
        if duration <= 0 {
            duration = Double(frames.count) * 0.1
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    static func frameDuration(source: CGImageSource, at index: Int) -> Double {
        let defaultDelay = 0.1
        guard let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any]
        else { return defaultDelay }

        let gifDelay: Double? = {
            guard let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
                return nil
            }
            let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
            return unclamped ?? clamped
        }()

        let webpDelay: Double? = {
            guard let webPProperties = frameProperties[kCGImagePropertyWebPDictionary] as? [CFString: Any] else {
                return nil
            }
            return webPProperties[kCGImagePropertyWebPDelayTime] as? Double
        }()

        let delay = gifDelay ?? webpDelay ?? defaultDelay

        // Some GIFs set tiny delays that cause excessive CPU usage and stutter.
        return delay < 0.02 ? defaultDelay : delay
    }
}
