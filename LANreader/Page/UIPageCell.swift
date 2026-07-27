import ComposableArchitecture
import AnimatedImage
import SwiftUI
import UIKit
import Logging
import ImageIO

private final class PreviewAwareAnimatedImageView: AnimatedImageView {
    var onFirstFrameRendered: (() -> Void)?
    private var hasRenderedFirstFrame = false

    func resetFirstFrameState() {
        hasRenderedFirstFrame = false
    }

    override func updateContents(for targetTimestamp: TimeInterval) {
        super.updateContents(for: targetTimestamp)

        guard !hasRenderedFirstFrame, layer.contents != nil else { return }
        hasRenderedFirstFrame = true
        onFirstFrameRendered?()
    }
}

class UIPageCell: UICollectionViewCell {
    static let reuseIdentifier = "UIPageCell"

    var store: StoreOf<PageFeature>?

    private let logger = Logger(label: "UIPageCell")
    private let imageService = ImageService.shared
    private static let animatedImageMemoryLimitMB: Double = 128
    private static let animatedImageConfiguration: AnimatedImage.Configuration = {
        var config = AnimatedImage.Configuration.unlimited
        config.maxMemoryUsage = .init(value: animatedImageMemoryLimitMB, unit: .megabytes)
        config.maxLevelOfIntegrity = 1
        config.interpolationQuality = .high
        return config
    }()

    private var observationTokens: Set<ObserveToken> = []
    private var fitPageWidth = false
    private var fitScreenHeightConstraint: NSLayoutConstraint!
    private var fitWidthAspectConstraint: NSLayoutConstraint?

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.minimumZoomScale = 1.0
        view.maximumZoomScale = 3.0
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        return view
    }()

    private let imageContainerView = UIView()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

    private let animatedImageView: PreviewAwareAnimatedImageView = {
        let view = PreviewAwareAnimatedImageView(frame: .zero)
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

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
        observationTokens.forEach { $0.cancel() }
        observationTokens.removeAll()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupImageView()
        animatedImageView.onFirstFrameRendered = { [weak self] in
            DispatchQueue.main.async {
                self?.imageView.isHidden = true
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupImageView() {
        contentView.addSubview(scrollView)
        scrollView.addSubview(imageContainerView)
        imageContainerView.addSubview(imageView)
        imageContainerView.addSubview(animatedImageView)
        contentView.addSubview(progressView)
        contentView.addSubview(progressViewLabel)

        scrollView.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        animatedImageView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressViewLabel.translatesAutoresizingMaskIntoConstraints = false

        fitScreenHeightConstraint = imageContainerView.heightAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.heightAnchor
        )

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor),

            imageContainerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageContainerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageContainerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageContainerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageContainerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            fitScreenHeightConstraint,

            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            animatedImageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            animatedImageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            animatedImageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            animatedImageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

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

    func configure(with store: StoreOf<PageFeature>, fitPageWidth: Bool) {
        // Tear down any existing observation from a previous page assignment
        cancelSubscriptions()
        animatedImageView.resetFirstFrameState()
        self.fitPageWidth = fitPageWidth
        resetImageLayout()
        self.store = store
        imageView.image = nil
        imageView.isHidden = true
        animatedImageView.image = nil
        animatedImageView.isHidden = true
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
        scrollView.setContentOffset(.zero, animated: false)
        setupObserve(store: store)
        renderCurrentState(store: store)
    }

    func setFitPageWidth(_ fitPageWidth: Bool) {
        guard self.fitPageWidth != fitPageWidth else { return }
        self.fitPageWidth = fitPageWidth
        scrollView.zoomScale = 1.0
        updateImageLayout(for: imageView.image?.size)
    }

    func setupObserve(store: StoreOf<PageFeature>) {
        SwiftNavigation.observe { [weak self] in
            guard let self else { return }
            let progress = store.progress
            guard self.store === store else { return }
            guard !store.imageLoaded else { return }

            imageView.isHidden = true
            animatedImageView.isHidden = true
            progressView.isHidden = false
            progressViewLabel.isHidden = false
            progressView.progress = Float(progress)
            progressViewLabel.text = progress > 1 ? String(localized: "translating") : String(
                format: "%.2f%%", progress * 100)
        }
        .store(in: &observationTokens)

        SwiftNavigation.observe { [weak self] in
            let status = store.translationStatus
            guard let self else { return }
            guard self.store === store else { return }
            guard !status.isEmpty else { return }

            progressViewLabel.text = status
        }
        .store(in: &observationTokens)

        SwiftNavigation.observe { [weak self] in
            let loaded = store.imageLoaded
            let pageMode = store.pageMode
            guard let self else { return }
            guard self.store === store else { return }
            guard loaded else { return }

            if store.errorMessage.isEmpty {
                progressView.isHidden = true
                progressViewLabel.isHidden = true
                renderImage(store: store, pageMode: pageMode)
            } else {
                imageView.isHidden = true
                animatedImageView.isHidden = true
                progressView.isHidden = true
                progressViewLabel.text = store.errorMessage
            }
        }
        .store(in: &observationTokens)
    }

    // swiftlint:disable function_body_length
    private func renderImage(store: StoreOf<PageFeature>, pageMode: PageMode) {
        animatedImageView.resetFirstFrameState()

        guard let contentPath = imageService.storedImagePath(
            folderUrl: store.folder,
            pageNumber: "\(store.pageNumber)"
        ) else {
            imageView.image = UIImage(systemName: "rectangle.slash")
            imageView.isHidden = false
            animatedImageView.image = nil
            animatedImageView.isHidden = true
            updateImageLayout(for: imageView.image?.size)
            return
        }

        if let splitSide = splitSide(for: pageMode) {
            imageView.image = imageService.splitImage(imageUrl: contentPath, side: splitSide)
                ?? UIImage(systemName: "rectangle.slash")
            imageView.isHidden = false
            animatedImageView.image = nil
            animatedImageView.isHidden = true
            updateImageLayout(for: imageView.image?.size)
            return
        }

        if imageService.isAnimatedImage(imageUrl: contentPath) {
            do {
                if let previewImage = previewImage(at: contentPath) {
                    imageView.image = previewImage
                } else {
                    imageView.image = UIImage(systemName: "rectangle.slash")
                }
                imageView.isHidden = false

                let image = try AnimatedImage(
                    contentsOf: contentPath,
                    withConfiguration: Self.animatedImageConfiguration
                )
                animatedImageView.image = image
                animatedImageView.isHidden = false
            } catch {
                logger.error("failed to render animated image. \(error)")
                if let staticImage = previewImage(at: contentPath) {
                    imageView.image = staticImage
                } else {
                    imageView.image = UIImage(systemName: "rectangle.slash")
                }
                imageView.isHidden = false
                animatedImageView.image = nil
                animatedImageView.isHidden = true
            }
        } else {
            if let staticImage = previewImage(at: contentPath) {
                imageView.image = staticImage
            } else {
                imageView.image = UIImage(systemName: "rectangle.slash")
            }
            imageView.isHidden = false
            animatedImageView.image = nil
            animatedImageView.isHidden = true
        }
        updateImageLayout(for: imageView.image?.size)
    }
    // swiftlint:enable function_body_length

    private func splitSide(for pageMode: PageMode) -> ImageSplitSide? {
        switch pageMode {
        case .left:
            return .left
        case .right:
            return .right
        case .loading, .normal, .error:
            return nil
        }
    }

    private func renderCurrentState(store: StoreOf<PageFeature>) {
        let pageMode = store.pageMode
        if store.errorMessage.isEmpty {
            if store.imageLoaded {
                progressView.isHidden = true
                progressViewLabel.isHidden = true
                renderImage(store: store, pageMode: pageMode)
            } else {
                imageView.isHidden = true
                animatedImageView.isHidden = true
                progressView.isHidden = false
                progressViewLabel.isHidden = false
                progressView.progress = Float(store.progress)
                progressViewLabel.text = store.translationStatus.isEmpty ?
                String(format: "%.2f%%", store.progress * 100) :
                store.translationStatus
            }
        } else {
            imageView.isHidden = true
            animatedImageView.isHidden = true
            progressView.isHidden = true
            progressViewLabel.isHidden = false
            progressViewLabel.text = store.errorMessage
        }
    }

    private func previewImage(at url: URL) -> UIImage? {
        if let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            return image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func resetImageLayout() {
        fitWidthAspectConstraint?.isActive = false
        fitWidthAspectConstraint = nil
        fitScreenHeightConstraint.isActive = true
    }

    private func updateImageLayout(for imageSize: CGSize?) {
        resetImageLayout()
        guard fitPageWidth,
              let imageSize,
              let aspectRatio = Self.fitWidthAspectRatio(for: imageSize) else {
            contentView.layoutIfNeeded()
            scrollView.setContentOffset(.zero, animated: false)
            return
        }

        fitScreenHeightConstraint.isActive = false
        fitWidthAspectConstraint = imageContainerView.heightAnchor.constraint(
            equalTo: imageContainerView.widthAnchor,
            multiplier: aspectRatio
        )
        fitWidthAspectConstraint?.isActive = true
        contentView.layoutIfNeeded()
        scrollView.setContentOffset(.zero, animated: false)
    }

    static func fitWidthAspectRatio(for imageSize: CGSize) -> CGFloat? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        return imageSize.height / imageSize.width
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelSubscriptions()
        animatedImageView.resetFirstFrameState()
        store = nil
        imageView.image = nil
        imageView.isHidden = true
        animatedImageView.image = nil
        animatedImageView.isHidden = true
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
        scrollView.setContentOffset(.zero, animated: false)
        fitPageWidth = false
        resetImageLayout()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        if let image = imageView.image {
            let width = layoutAttributes.frame.width
            let height = width * (image.size.height / image.size.width)
            attributes.frame.size.height = height
        }
        return attributes
    }
}

extension UIPageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageContainerView
    }
}
