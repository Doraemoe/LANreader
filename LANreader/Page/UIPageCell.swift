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

enum StampOverlayPositioning {
    static func displayedPosition(
        _ position: ArchiveStampPosition,
        pageMode: PageMode
    ) -> ArchiveStampPosition? {
        switch pageMode {
        case .left:
            guard position.horizontalPercentage < 50 else { return nil }
            return ArchiveStampPosition(
                horizontalPercentage: position.horizontalPercentage * 2,
                verticalPercentage: position.verticalPercentage
            )
        case .right:
            guard position.horizontalPercentage >= 50 else { return nil }
            return ArchiveStampPosition(
                horizontalPercentage: (position.horizontalPercentage - 50) * 2,
                verticalPercentage: position.verticalPercentage
            )
        case .loading, .normal, .error:
            return position
        }
    }

    static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect? {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func sourcePosition(
        at point: CGPoint,
        pageMode: PageMode,
        imageSize: CGSize,
        in bounds: CGRect
    ) -> ArchiveStampPosition? {
        guard let imageRect = aspectFitRect(imageSize: imageSize, in: bounds),
              imageRect.contains(point) else {
            return nil
        }

        let displayedHorizontal = min(
            max(Double((point.x - imageRect.minX) / imageRect.width) * 100, 0),
            100
        )
        let vertical = min(
            max(Double((point.y - imageRect.minY) / imageRect.height) * 100, 0),
            100
        )
        let sourceHorizontal: Double
        switch pageMode {
        case .left:
            sourceHorizontal = min(displayedHorizontal / 2, 50.nextDown)
        case .right:
            sourceHorizontal = 50 + displayedHorizontal / 2
        case .normal:
            sourceHorizontal = displayedHorizontal
        case .loading, .error:
            return nil
        }
        return ArchiveStampPosition(
            horizontalPercentage: sourceHorizontal,
            verticalPercentage: vertical
        )
    }
}

private final class StampCommentLabel: UILabel {
    private let contentInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let contentSize = CGSize(
            width: max(0, size.width - contentInsets.left - contentInsets.right),
            height: max(0, size.height - contentInsets.top - contentInsets.bottom)
        )
        let labelSize = super.sizeThatFits(contentSize)
        return CGSize(
            width: labelSize.width + contentInsets.left + contentInsets.right,
            height: labelSize.height + contentInsets.top + contentInsets.bottom
        )
    }
}

private final class StampOverlayView: UIView {
    private struct DisplayedStamp {
        let sourceIndex: Int
        let stamp: ArchiveStamp
        let position: ArchiveStampPosition
    }

    private let markerSize: CGFloat = 30
    private let calloutSpacing: CGFloat = 6
    private var stamps: [ArchiveStamp] = []
    private var displayedStamps: [DisplayedStamp] = []
    private var markerButtons: [UIButton] = []
    private var selectedSourceIndex: Int?
    private var imageSize: CGSize?
    private var pageMode: PageMode = .normal

    private let commentLabel: StampCommentLabel = {
        let label = StampCommentLabel()
        label.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .callout)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.layer.borderWidth = 1
        label.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        label.clipsToBounds = true
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(commentLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(stamps: [ArchiveStamp], pageMode: PageMode, imageSize: CGSize?) {
        let contentsChanged = self.stamps != stamps || self.pageMode != pageMode
        self.stamps = stamps
        self.pageMode = pageMode
        self.imageSize = imageSize
        if contentsChanged {
            rebuildMarkers()
        }
        setNeedsLayout()
    }

    func clear() {
        stamps = []
        displayedStamps = []
        imageSize = nil
        selectedSourceIndex = nil
        markerButtons.forEach { $0.removeFromSuperview() }
        markerButtons = []
        commentLabel.isHidden = true
        commentLabel.text = nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        markerButtons.contains { !$0.isHidden && $0.frame.insetBy(dx: -4, dy: -4).contains(point) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let imageSize,
              let imageRect = StampOverlayPositioning.aspectFitRect(imageSize: imageSize, in: bounds) else {
            markerButtons.forEach { $0.isHidden = true }
            commentLabel.isHidden = true
            return
        }

        for (index, displayedStamp) in displayedStamps.enumerated() {
            let button = markerButtons[index]
            let point = CGPoint(
                x: imageRect.minX
                    + imageRect.width * CGFloat(displayedStamp.position.horizontalPercentage / 100),
                y: imageRect.minY
                    + imageRect.height * CGFloat(displayedStamp.position.verticalPercentage / 100)
            )
            let origin = CGPoint(
                x: min(max(point.x - markerSize / 2, imageRect.minX), imageRect.maxX - markerSize),
                y: min(max(point.y - markerSize / 2, imageRect.minY), imageRect.maxY - markerSize)
            )
            button.frame = CGRect(origin: origin, size: CGSize(width: markerSize, height: markerSize))
            button.isHidden = false
        }

        layoutComment(in: imageRect)
    }

    private func rebuildMarkers() {
        markerButtons.forEach { $0.removeFromSuperview() }
        markerButtons = []
        displayedStamps = stamps.enumerated().compactMap { index, stamp in
            guard let position = stamp.normalizedPosition,
                  let displayedPosition = StampOverlayPositioning.displayedPosition(
                    position,
                    pageMode: pageMode
                  ) else {
                return nil
            }
            return DisplayedStamp(sourceIndex: index, stamp: stamp, position: displayedPosition)
        }

        if !displayedStamps.contains(where: { $0.sourceIndex == selectedSourceIndex }) {
            selectedSourceIndex = nil
        }

        for displayedStamp in displayedStamps {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "seal.fill"), for: .normal)
            button.tintColor = .white
            button.backgroundColor = .systemOrange
            button.layer.cornerRadius = markerSize / 2
            button.layer.cornerCurve = .continuous
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.3
            button.layer.shadowRadius = 2
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.accessibilityLabel = displayedStamp.stamp.content
            button.addAction(
                UIAction { [weak self] _ in
                    self?.toggleComment(for: displayedStamp.sourceIndex)
                },
                for: .touchUpInside
            )
            addSubview(button)
            markerButtons.append(button)
        }
        bringSubviewToFront(commentLabel)
    }

    private func toggleComment(for sourceIndex: Int) {
        selectedSourceIndex = selectedSourceIndex == sourceIndex ? nil : sourceIndex
        setNeedsLayout()
    }

    private func layoutComment(in imageRect: CGRect) {
        guard let selectedSourceIndex,
              let selectedIndex = displayedStamps.firstIndex(where: { $0.sourceIndex == selectedSourceIndex }),
              displayedStamps.indices.contains(selectedIndex),
              markerButtons.indices.contains(selectedIndex) else {
            commentLabel.isHidden = true
            commentLabel.text = nil
            return
        }

        let content = displayedStamps[selectedIndex].stamp.content
        guard !content.isEmpty else {
            commentLabel.isHidden = true
            commentLabel.text = nil
            return
        }

        commentLabel.text = content
        let maxWidth = min(280, imageRect.width)
        let fittedSize = commentLabel.sizeThatFits(
            CGSize(width: maxWidth, height: max(imageRect.height, 1))
        )
        let calloutSize = CGSize(
            width: min(fittedSize.width, maxWidth),
            height: min(fittedSize.height, imageRect.height)
        )
        let markerFrame = markerButtons[selectedIndex].frame
        let proposedY = markerFrame.maxY + calloutSpacing
        let verticalOrigin = proposedY + calloutSize.height <= imageRect.maxY
            ? proposedY
            : max(imageRect.minY, markerFrame.minY - calloutSpacing - calloutSize.height)
        let horizontalOrigin = min(
            max(markerFrame.midX - calloutSize.width / 2, imageRect.minX),
            imageRect.maxX - calloutSize.width
        )
        commentLabel.frame = CGRect(
            origin: CGPoint(x: horizontalOrigin, y: verticalOrigin),
            size: calloutSize
        )
        commentLabel.isHidden = false
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
    private var onCreateStamp: ((ArchiveStampPosition) -> Void)?
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

    private let stampOverlayView = StampOverlayView()

    private lazy var stampCreationGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleStampLongPress(_:)))
        gesture.delegate = self
        return gesture
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
        setupStampOverlay()
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

    private func setupStampOverlay() {
        imageContainerView.addGestureRecognizer(stampCreationGesture)
        imageContainerView.addSubview(stampOverlayView)
        stampOverlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stampOverlayView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            stampOverlayView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            stampOverlayView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            stampOverlayView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor)
        ])
    }

    func configure(
        with store: StoreOf<PageFeature>,
        fitPageWidth: Bool,
        showsStamps: Bool,
        onCreateStamp: @escaping (ArchiveStampPosition) -> Void
    ) {
        // Tear down any existing observation from a previous page assignment
        cancelSubscriptions()
        animatedImageView.resetFirstFrameState()
        self.onCreateStamp = onCreateStamp
        self.fitPageWidth = fitPageWidth
        stampOverlayView.clear()
        stampOverlayView.isHidden = !showsStamps
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
        if showsStamps {
            store.send(.loadStamps)
        }
    }

    @objc private func handleStampLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        requestStampCreation(at: gesture.location(in: imageContainerView))
    }

    func requestStampCreation(at location: CGPoint) {
        guard let store,
              !store.cached,
              store.imageLoaded,
              store.errorMessage.isEmpty,
              let imageSize = imageView.image?.size,
              let position = StampOverlayPositioning.sourcePosition(
                at: location,
                pageMode: store.pageMode,
                imageSize: imageSize,
                in: imageContainerView.bounds
              ) else {
            return
        }
        onCreateStamp?(position)
    }

    func setFitPageWidth(_ fitPageWidth: Bool) {
        guard self.fitPageWidth != fitPageWidth else { return }
        self.fitPageWidth = fitPageWidth
        scrollView.zoomScale = 1.0
        updateImageLayout(for: imageView.image?.size)
    }

    func setShowsStamps(_ showsStamps: Bool) {
        stampOverlayView.isHidden = !showsStamps
        if showsStamps {
            store?.send(.loadStamps)
            updateStampOverlay()
        }
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

        observeStamps(store: store)

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

    private func observeStamps(store: StoreOf<PageFeature>) {
        SwiftNavigation.observe { [weak self] in
            let stamps = store.stamps
            let pageMode = store.pageMode
            guard let self else { return }
            guard self.store === store else { return }
            self.stampOverlayView.configure(
                stamps: stamps,
                pageMode: pageMode,
                imageSize: self.imageView.image?.size
            )
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
            updateStampOverlay()
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
        updateStampOverlay()
    }

    private func updateStampOverlay() {
        guard let store else { return }
        stampOverlayView.configure(
            stamps: store.stamps,
            pageMode: store.pageMode,
            imageSize: imageView.image?.size
        )
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
        onCreateStamp = nil
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
        stampOverlayView.clear()
        stampOverlayView.isHidden = true
        resetImageLayout()
    }
}

extension UIPageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageContainerView
    }
}
extension UIPageCell: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var touchedView = touch.view
        while let currentView = touchedView {
            if currentView is UIControl {
                return false
            }
            guard currentView !== imageContainerView else { break }
            touchedView = currentView.superview
        }
        return true
    }
}
